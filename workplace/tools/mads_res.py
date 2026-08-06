#!/usr/bin/env python3
"""MADS 引擎資源存取（HAG 封裝、MadsPack 容器、FAB 壓縮）。

所有格式皆逐行對照 ScummVM 2.8.0 原始碼實作，出處註記在各函式：
  engines/mads/resources.cpp   HagArchive::loadIndex()
  engines/mads/compression.cpp MadsPack::initialize() / FabDecompressor::decompress()
"""
import os
import struct
import sys

MADSCONCAT = b"MADSCONCAT"
MADSPACK = b"MADSPACK"


def u16(b, o=0):
    return struct.unpack_from("<H", b, o)[0]


def u32(b, o=0):
    return struct.unpack_from("<I", b, o)[0]


def to_signed32(v):
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


# --------------------------------------------------------------------------
# FAB 解壓（compression.cpp:108 FabDecompressor::decompress）
# --------------------------------------------------------------------------
class FabDecompressor:
    def __init__(self, src):
        self._src = src
        self._src_size = len(src)
        self._src_p = 6
        self._bits_left = 16
        self._bit_buffer = u16(src, 4)

    def _get_bit(self):
        self._bits_left -= 1
        if self._bits_left == 0:
            if self._src_p == self._src_size:
                raise ValueError("FAB: 讀過輸入緩衝區結尾")
            self._bit_buffer = ((u16(self._src, self._src_p) << 1) |
                                (self._bit_buffer & 1)) & 0xFFFFFFFF
            self._src_p += 2
            self._bits_left = 16
        bit = self._bit_buffer & 1
        self._bit_buffer >>= 1
        return bit

    def decompress(self, dest_size):
        src = self._src
        if src[0:3] != b"FAB":
            raise ValueError("FAB: 缺少 FAB 標頭")
        shift_val = src[3]
        if not (10 <= shift_val <= 13):
            raise ValueError("FAB: shift start 非法 (%d)" % shift_val)

        copy_ofs_shift = 16 - shift_val
        copy_ofs_mask = (0xFF << (shift_val - 8)) & 0xFF   # C 端宣告為 byte，會截斷
        copy_len_mask = (1 << copy_ofs_shift) - 1

        dest = bytearray()
        while True:
            if self._get_bit() == 0:
                if self._get_bit() == 0:
                    copy_len = ((self._get_bit() << 1) | self._get_bit()) + 2
                    copy_ofs = to_signed32(src[self._src_p] | 0xFFFFFF00)
                    self._src_p += 1
                else:
                    s0 = src[self._src_p]
                    s1 = src[self._src_p + 1]
                    copy_ofs = (((s1 >> copy_ofs_shift) | copy_ofs_mask) << 8) | s0
                    copy_len = s1 & copy_len_mask
                    self._src_p += 2
                    if copy_len == 0:
                        copy_len = src[self._src_p]
                        self._src_p += 1
                        if copy_len == 0:
                            break
                        elif copy_len == 1:
                            continue
                        else:
                            copy_len += 1
                    else:
                        copy_len += 2
                    copy_ofs = to_signed32(copy_ofs | 0xFFFF0000)

                for _ in range(copy_len):
                    if len(dest) == dest_size:
                        raise ValueError("FAB: 解壓資料超出宣告大小")
                    dest.append(dest[len(dest) + copy_ofs])
            else:
                if self._src_p == self._src_size:
                    raise ValueError("FAB: 讀過輸入緩衝區結尾")
                if len(dest) == dest_size:
                    raise ValueError("FAB: 解壓資料超出宣告大小")
                dest.append(src[self._src_p])
                self._src_p += 1

        if len(dest) != dest_size:
            raise ValueError("FAB: 解壓長度 %d != 宣告 %d" % (len(dest), dest_size))
        return bytes(dest)


def fab_decompress(src, dest_size):
    return FabDecompressor(src).decompress(dest_size)


# --------------------------------------------------------------------------
# MadsPack 容器（compression.cpp:53 MadsPack::initialize）
# --------------------------------------------------------------------------
def is_madspack(data):
    return data[0:8] == MADSPACK


def madspack_items(data):
    """回傳 [(type, priority, data_bytes), ...]。"""
    if not is_madspack(data):
        raise ValueError("非 MADSPACK 資源")
    count = u16(data, 14)
    header = data[16:16 + 0xA0]
    pos = 16 + 0xA0
    items = []
    for i in range(count):
        off = i * 10
        ctype = header[off]
        priority = header[off + 1]
        size = u32(header, off + 2)
        csize = u32(header, off + 6)
        src = data[pos:pos + csize]
        pos += csize
        if ctype == 0:
            out = src
        elif ctype == 1:
            out = fab_decompress(src, size)
        else:
            raise ValueError("未知壓縮型別 %d" % ctype)
        items.append((ctype, priority, out))
    return items


# --------------------------------------------------------------------------
# HAG 封裝（resources.cpp:152 HagArchive::loadIndex）
# --------------------------------------------------------------------------
class HagFile:
    def __init__(self, path):
        self.path = path
        self.name = os.path.basename(path)
        with open(path, "rb") as f:
            self._raw = f.read()
        if self._raw[0:10] != MADSCONCAT:
            raise ValueError("%s 不是 HAG 檔" % path)
        count = u16(self._raw, 16)
        self.entries = []          # (name, offset, size)
        pos = 18
        for _ in range(count):
            offset = u32(self._raw, pos)
            size = u32(self._raw, pos + 4)
            raw_name = self._raw[pos + 8:pos + 22]
            name = raw_name.split(b"\0")[0].decode("latin-1")
            pos += 22
            self.entries.append((name, offset, size))

    def read(self, name):
        name = name.upper().lstrip("*")
        for ename, offset, size in self.entries:
            if ename.upper() == name:
                return self._raw[offset:offset + size]
        return None


class HagArchive:
    """把 GLOBAL.HAG + SECTION*.HAG 當成單一命名空間。"""

    def __init__(self, game_dir):
        self.game_dir = game_dir
        self.hags = []
        names = ["GLOBAL.HAG"] + ["SECTION%d.HAG" % i for i in range(0, 11)] + ["SPEECH.HAG"]
        actual = {f.upper(): f for f in os.listdir(game_dir)}
        for want in names:
            if want in actual:
                self.hags.append(HagFile(os.path.join(game_dir, actual[want])))

    def list_all(self):
        out = []
        for h in self.hags:
            for name, offset, size in h.entries:
                out.append((h.name, name, offset, size))
        return out

    def read(self, name):
        for h in self.hags:
            data = h.read(name)
            if data is not None:
                return data
        return None

    def read_unpacked(self, name):
        """讀資源；若是 MadsPack 容器則回傳解開後的 item 0。"""
        data = self.read(name)
        if data is None:
            return None
        if is_madspack(data):
            return madspack_items(data)[0][2]
        return data


if __name__ == "__main__":
    game = sys.argv[1] if len(sys.argv) > 1 else "game"
    arc = HagArchive(game)
    print("HAG 檔:", ", ".join(h.name for h in arc.hags))
    rows = arc.list_all()
    print("資源總數:", len(rows))
    for hag, name, off, size in rows:
        print("%-14s %-14s off=%-9d size=%d" % (hag, name, off, size))

# Writes favicon.ico, the icon examples/site-icon embeds: a 16 by 16 orange
# disc ringed in dark brown, as one 32-bit image in an ICO file.
#
# The ring's colour, 0x1a0d0a, is stored as the bytes 0x0a 0x0d 0x1a, a line
# feed, a carriage return and an end-of-file mark, so a transcript comparing the
# answered body with this file shows no byte of it was taken for text.
#
# Run from this directory: python3 make-icon.py
import struct

SIZE = 16
ORANGE = bytes((0x1F, 0x8C, 0xF2, 0xFF))  # blue, green, red, alpha
RING = bytes((0x0A, 0x0D, 0x1A, 0xFF))
CLEAR = bytes(4)

pixels = bytearray()
for y in range(SIZE - 1, -1, -1):  # a bitmap's rows run bottom to top
    for x in range(SIZE):
        distance = ((x - 7.5) ** 2 + (y - 7.5) ** 2) ** 0.5
        pixels += ORANGE if distance <= 5.5 else RING if distance <= 7.5 else CLEAR

mask = bytes(4 * SIZE)  # every pixel is drawn by its alpha
header = struct.pack("<IiiHHIIiiII", 40, SIZE, 2 * SIZE, 1, 32, 0, len(pixels) + len(mask), 0, 0, 0, 0)
image = header + pixels + mask
icon = struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", SIZE, SIZE, 0, 0, 1, 32, len(image), 22) + image

with open("favicon.ico", "wb") as out:
    out.write(icon)

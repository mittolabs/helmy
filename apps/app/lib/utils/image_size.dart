/// The width and height of a PNG or JPEG, read from its header; null when
/// it is neither.
(int, int)? imageSize(List<int> b) {
  int be16(int i) => b[i] << 8 | b[i + 1];
  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
    return (be16(16) << 16 | be16(18), be16(20) << 16 | be16(22));
  }
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    // Start of frame: every SOFn but the DHT, JPG and DAC markers.
    if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
      return (be16(i + 7), be16(i + 5));
    }
    i += 2 + be16(i + 2);
  }
  return null;
}

// Tarayıcı dışı (birim testleri, mobil): bellekte tutulur.
final Map<String, String> _mem = {};

String? panelStoreRead(String key) => _mem[key];

void panelStoreWrite(String key, String value) => _mem[key] = value;

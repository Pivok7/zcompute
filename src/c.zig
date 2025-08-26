pub fn cStringEql(str_1: [*:0]const u8, str_2: [*]const u8) bool {
    var i: usize = 0;
    while (str_1[i] == str_2[i]) : (i += 1) {
        if (str_1[i] == '\x00') return true;
    }
    return false;
}

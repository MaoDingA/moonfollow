///|
fn int_fails(s : StringView) -> Bool {
  try {
    ignore(@parse.parse_int(s))
    false
  } catch {
    _ => true
  }
}

///|
fn double_fails(s : StringView) -> Bool {
  try {
    ignore(@parse.parse_double(s))
    false
  } catch {
    _ => true
  }
}

///|
test "parse: ints, signs, overflow, garbage" {
  inspect(@parse.parse_int("0"), content="0")
  inspect(@parse.parse_int("320"), content="320")
  inspect(@parse.parse_int("30000"), content="30000")
  inspect(@parse.parse_int("-1001"), content="-1001")
  inspect(@parse.parse_int("+42"), content="42")
  inspect(@parse.parse_int("00"), content="0")
  inspect(int_fails(""), content="true")
  inspect(int_fails("12x"), content="true")
  inspect(int_fails("2147483648"), content="true")
}

///|
test "parse: decimals without exponent" {
  inspect(@parse.parse_double("48000"), content="48000")
  inspect(@parse.parse_double("30").to_string(), content="30")
  inspect((@parse.parse_double("29.97") - 29.97).abs() < 0.0001, content="true")
  inspect((@parse.parse_double("0.5") - 0.5).abs() < 0.000001, content="true")
  inspect((@parse.parse_double("-0.2") + 0.2).abs() < 0.000001, content="true")
  inspect(double_fails("."), content="true")
  inspect(double_fails("1.2.3"), content="true")
  inspect(double_fails("1e5"), content="true")
}

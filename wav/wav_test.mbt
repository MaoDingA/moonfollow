///|
test "encode/parse roundtrip 16-bit stereo" {
  let samples : Array[Double] = []
  for i in 0..<200 {
    let t = i.to_double() / 48000.0
    let v = 0.5 * @math.sin(2.0 * @math.PI * 440.0 * t)
    samples.push(v)
    samples.push(v * 0.8)
  }
  let wav : @wav.WavData = { sample_rate: 48000, channels: 2, samples, }
  let back = @wav.WavData::parse(wav.encode_pcm16())
  inspect(back.sample_rate, content="48000")
  inspect(back.channels, content="2")
  inspect(back.samples.length(), content="400")
  for i in 0..<400 {
    if (back.samples[i] - wav.samples[i]).abs() > 1.5 / 32767.0 {
      fail("sample \{i} drifted: \{wav.samples[i]} vs \{back.samples[i]}")
    }
  }
}

///|
test "parse 24-bit mono" {
  let buf = Buffer::Buffer()
  buf.write_bytes(b"RIFF")
  buf.write_int_le(36 + 6) // two 24-bit mono samples
  buf.write_bytes(b"WAVE")
  buf.write_bytes(b"fmt ")
  buf.write_int_le(16)
  buf.write_int16_le(1)
  buf.write_int16_le(1)
  buf.write_int_le(48000)
  buf.write_int_le(48000 * 3)
  buf.write_int16_le(3)
  buf.write_int16_le(24)
  buf.write_bytes(b"data")
  buf.write_int_le(6)
  buf.write_bytes(b"\xff\xff\x7f") // max sample
  buf.write_bytes(b"\x00\x00\x80") // min sample
  let wav = @wav.WavData::parse(buf.to_bytes())
  inspect(wav.sample_rate, content="48000")
  inspect(wav.channels, content="1")
  inspect(wav.samples.length(), content="2")
  inspect(wav.samples[0] > 0.9999, content="true")
  inspect(wav.samples[1].to_string(), content="-1")
}

///|
fn mini_wav(format : Int, bits : Int, data : Bytes) -> Bytes {
  let buf = Buffer::Buffer()
  buf.write_bytes(b"RIFF")
  buf.write_int_le(36 + data.length())
  buf.write_bytes(b"WAVE")
  buf.write_bytes(b"fmt ")
  buf.write_int_le(16)
  buf.write_int16_le(Int16::from_int(format))
  buf.write_int16_le(1)
  buf.write_int_le(48000)
  buf.write_int_le(48000 * (bits / 8))
  buf.write_int16_le(Int16::from_int(bits / 8))
  buf.write_int16_le(Int16::from_int(bits))
  buf.write_bytes(b"data")
  buf.write_int_le(data.length())
  buf.write_bytes(data)
  buf.to_bytes()
}

///|
test "rejects garbage and unsupported formats" {
  try ignore(@wav.WavData::parse(b"NOPE NOT A WAV!!!")) catch {
    err =>
      inspect(
        err.to_string(),
        content="not a WAV file: missing RIFF/WAVE header",
      )
  } noraise {
    _ => fail("expected to fail")
  }
  try ignore(@wav.WavData::parse(mini_wav(3, 32, b"\x00\x00\x80\x3f"))) catch {
    err =>
      inspect(
        err.to_string(),
        content="unsupported WAV format: format code 3 (only uncompressed PCM; convert float/compressed WAV first)",
      )
  } noraise {
    _ => fail("expected to fail")
  }
  try ignore(@wav.WavData::parse(mini_wav(1, 8, b"\x80\x80"))) catch {
    err =>
      inspect(
        err.to_string(),
        content="unsupported WAV format: 8-bit samples (only 16/24-bit PCM)",
      )
  } noraise {
    _ => fail("expected to fail")
  }
  // data size not a multiple of the frame size
  try ignore(@wav.WavData::parse(mini_wav(1, 16, b"\x00"))) catch {
    err =>
      inspect(
        err.to_string(),
        content="not a WAV file: data size 1 not a multiple of frame size 2",
      )
  } noraise {
    _ => fail("expected to fail")
  }
  // truncated chunk: header declares more data than the file holds
  let full = mini_wav(1, 16, b"\x00\x00\x00\x00")
  let cut = full[:full.length() - 4].to_owned()
  try ignore(@wav.WavData::parse(cut)) catch {
    err =>
      inspect(
        err.to_string(),
        content="not a WAV file: truncated chunk at byte 36",
      )
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
fn put_u16(b : Buffer, v : Int) -> Unit {
  b.write_byte((v & 0xff).to_byte())
  b.write_byte(((v >> 8) & 0xff).to_byte())
}

///|
fn put_u32(b : Buffer, v : Int) -> Unit {
  b.write_byte((v & 0xff).to_byte())
  b.write_byte(((v >> 8) & 0xff).to_byte())
  b.write_byte(((v >> 16) & 0xff).to_byte())
  b.write_byte(((v >> 24) & 0xff).to_byte())
}

///|
test "wav: streaming data-chunk size placeholder is clamped to the file" {
  // ffmpeg writing to a pipe sets RIFF/data sizes to 0xFFFFFFFF
  let b = Buffer::Buffer()
  b.write_bytes(b"RIFF")
  put_u32(b, -1) // RIFF size placeholder
  b.write_bytes(b"WAVE")
  b.write_bytes(b"fmt ")
  put_u32(b, 16)
  put_u16(b, 1) // PCM
  put_u16(b, 1) // mono
  put_u32(b, 16000) // sample rate
  put_u32(b, 32000) // byte rate
  put_u16(b, 2) // block align
  put_u16(b, 16) // bits
  b.write_bytes(b"data")
  put_u32(b, -1) // data size placeholder
  put_u16(b, 0x4000) // 0.5
  put_u16(b, 0xc000) // -0.5 (as unsigned 0xc000)
  let wav = @wav.WavData::parse(b.to_bytes())
  inspect(wav.sample_rate, content="16000")
  inspect(wav.channels, content="1")
  inspect(wav.samples.length(), content="2")
  inspect((wav.samples[0] - 0.5).abs() < 0.001, content="true")
  inspect((wav.samples[1] + 0.5).abs() < 0.001, content="true")
}

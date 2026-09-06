///|
pub(all) suberror WavError {
  NotWav(detail~ : String)
  UnsupportedFormat(detail~ : String)
} derive(Debug, Eq)

///|
pub impl Show for WavError with fn output(self, logger) {
  match self {
    NotWav(detail~) => logger <+ "not a WAV file: \{detail}"
    UnsupportedFormat(detail~) => logger <+ "unsupported WAV format: \{detail}"
  }
}

///|
/// Decoded WAV audio: interleaved samples in [-1, 1].

///|
pub(all) struct WavData {
  sample_rate : Int
  channels : Int
  samples : Array[Double]
} derive(Debug, Eq)

///|
fn tag_is(view : BytesView, at : Int, tag : Bytes) -> Bool {
  for k in 0..<4 {
    if view[at + k] != tag[k] {
      return false
    }
  }
  true
}

///|
fn read_u16(view : BytesView, at : Int) -> Int {
  view[at].to_int() + view[at + 1].to_int() * 256
}

///|
fn read_u32(view : BytesView, at : Int) -> Int {
  view[at].to_int() +
  view[at + 1].to_int() * 0x100 +
  view[at + 2].to_int() * 0x10000 +
  view[at + 3].to_int() * 0x1000000
}

///|
fn not_wav(detail : String) -> Unit raise WavError {
  raise WavError::NotWav(detail~)
}

///|
/// Parse a RIFF/WAVE file with uncompressed PCM (16- or 24-bit) data.

///|
pub fn WavData::parse(bytes : Bytes) -> WavData raise WavError {
  let view = bytes[:]
  if view.length() < 12 ||
    !tag_is(view, 0, b"RIFF") ||
    !tag_is(view, 8, b"WAVE") {
    not_wav("missing RIFF/WAVE header")
  }
  let mut pos = 12
  let mut fmt_seen = false
  let mut channels = 0
  let mut sample_rate = 0
  let mut bits = 0
  let mut format = 0
  let mut data_start = -1
  let mut data_size = 0
  while pos + 8 <= view.length() {
    let mut size = read_u32(view, pos + 4)
    if size < 0 {
      // streaming encoders (ffmpeg writing to a pipe) leave the data chunk
      // size as the 0xFFFFFFFF sentinel; the samples then run to end of file
      if tag_is(view, pos, b"data") {
        size = view.length() - pos - 8
      } else {
        not_wav("truncated chunk at byte \{pos}")
      }
    } else if pos + 8 + size > view.length() {
      not_wav("truncated chunk at byte \{pos}")
    }
    if tag_is(view, pos, b"fmt ") {
      if size < 16 {
        not_wav("fmt chunk too short")
      }
      format = read_u16(view, pos + 8)
      channels = read_u16(view, pos + 10)
      sample_rate = read_u32(view, pos + 12)
      bits = read_u16(view, pos + 22)
      fmt_seen = true
    } else if tag_is(view, pos, b"data") {
      data_start = pos + 8
      data_size = size
    }
    pos = pos + 8 + size
    if size % 2 == 1 {
      pos = pos + 1 // chunks are word-aligned
    }
  }
  if !fmt_seen {
    not_wav("no fmt chunk")
  }
  if data_start < 0 {
    not_wav("no data chunk")
  }
  if channels < 1 || channels > 2 {
    raise WavError::UnsupportedFormat(
      detail="\{channels} channels (only mono/stereo)",
    )
  }
  if format != 1 {
    raise WavError::UnsupportedFormat(
      detail="format code \{format} (only uncompressed PCM; convert float/compressed WAV first)",
    )
  }
  if bits != 16 && bits != 24 {
    raise WavError::UnsupportedFormat(
      detail="\{bits}-bit samples (only 16/24-bit PCM)",
    )
  }
  let bytes_per_sample = bits / 8
  let frame_size = bytes_per_sample * channels
  if data_size % frame_size != 0 {
    not_wav("data size \{data_size} not a multiple of frame size \{frame_size}")
  }
  let count = data_size / frame_size * channels
  let samples : Array[Double] = []
  for i in 0..<count {
    let at = data_start + i * bytes_per_sample
    let raw = if bits == 16 {
      let v = read_u16(view, at)
      let signed = if v >= 0x8000 { v - 0x10000 } else { v }
      signed.to_double() / 32768.0
    } else {
      let v = view[at].to_int() +
        view[at + 1].to_int() * 0x100 +
        view[at + 2].to_int() * 0x10000
      let signed = if v >= 0x800000 { v - 0x1000000 } else { v }
      signed.to_double() / 8388608.0
    }
    samples.push(raw)
  }
  { sample_rate, channels, samples, }
}

///|
/// Encode as 16-bit PCM WAV.

///|
pub fn WavData::encode_pcm16(self : WavData) -> Bytes {
  let buf = Buffer::Buffer()
  let bytes_per_sample = 2
  let block_align = bytes_per_sample * self.channels
  let data_size = self.samples.length() * bytes_per_sample
  buf.write_bytes(b"RIFF")
  buf.write_int_le(36 + data_size)
  buf.write_bytes(b"WAVE")
  buf.write_bytes(b"fmt ")
  buf.write_int_le(16)
  buf.write_int16_le(1) // PCM
  buf.write_int16_le(Int16::from_int(self.channels))
  buf.write_int_le(self.sample_rate)
  buf.write_int_le(self.sample_rate * block_align)
  buf.write_int16_le(Int16::from_int(block_align))
  buf.write_int16_le(16)
  buf.write_bytes(b"data")
  buf.write_int_le(data_size)
  for sample in self.samples {
    let clamped = if sample <= -1.0 {
      -32768.0
    } else if sample >= 1.0 {
      32767.0
    } else {
      sample * 32767.0
    }
    buf.write_int16_le(Int16::from_int(clamped.round().to_int()))
  }
  buf.to_bytes()
}

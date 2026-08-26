/**
 * Reading the text out of a submitted document.
 *
 * Until now the model saw a filename, a content type and whatever note the
 * uploader attached. It grounded findings in documents it had never read. This
 * is what lets it read them.
 *
 * Three rules shape everything below.
 *
 * **Extraction never fails an upload.** A document that cannot be read is
 * still evidence: it is still hashed, still stored, still citable, and the
 * other party can still see that it exists. A corrupt file must not stop
 * someone filing their contract.
 *
 * **The result says which kind of nothing it is.** "No text because this is a
 * photograph" and "no text because we could not read this file" are different
 * facts about a case. The second means there is content the model is not
 * seeing, which is a reason for it to be less confident, so the status travels
 * with the row all the way into the prompt.
 *
 * **Nothing about the text is stated inside the text.** Extracted content is
 * written by a party to the dispute. A truncation marker appended to the
 * content could equally have been typed by the uploader, so truncation is
 * reported through the status, which the prompt renders outside the quoted
 * block. The same reasoning already governs claims and notes.
 */

/**
 * Per-document ceiling, in characters.
 *
 * Roughly five thousand tokens. The prompt carries every piece of evidence on
 * the case, so the real bound on prompt size is this times the number of
 * documents; a contract with thirty of them will produce a large call.
 * Capping the document count is a policy question and belongs with the
 * escalation policy, not here, where the only question is one file at a time.
 */
export const MAX_EXTRACTED_CHARS = 20_000

/** Content types this can read. Anything else is reported as unsupported. */
export const EXTRACTABLE_CONTENT_TYPES: readonly string[] = [
  'text/plain',
  'text/markdown',
  'text/csv',
]

export type ExtractionStatus = 'extracted' | 'truncated' | 'unsupported' | 'failed'

export interface Extraction {
  readonly status: ExtractionStatus
  /** The text, when there is any. Null for `unsupported` and `failed`. */
  readonly text: string | null
  /** Why it could not be read. Null unless the status is `failed`. */
  readonly reason: string | null
}

const UNSUPPORTED: Extraction = { status: 'unsupported', text: null, reason: null }

function failed(reason: string): Extraction {
  return { status: 'failed', text: null, reason }
}

const TAB = 9
const LINE_FEED = 10
const CARRIAGE_RETURN = 13
const NUL = String.fromCharCode(0)

/**
 * Characters with no business in a prompt.
 *
 * Tab and newline survive because they carry structure. The rest of the C0 and
 * C1 ranges go, and so do the zero-width and bidirectional formatting
 * characters: those are invisible to a person reviewing the document and
 * present to the model reading it, which is exactly the gap someone would use
 * to hide an instruction inside an otherwise innocent file.
 *
 * Written as code point comparisons rather than a regular expression, because
 * a character class of invisible characters is a class nobody can review.
 */
function isDropped(code: number): boolean {
  if (code === TAB || code === LINE_FEED) return false
  if (code <= 0x1f) return true // C0 controls
  if (code >= 0x7f && code <= 0x9f) return true // DEL and the C1 controls
  if (code >= 0x200b && code <= 0x200f) return true // zero width, LRM, RLM
  if (code >= 0x202a && code <= 0x202e) return true // bidi embedding and override
  if (code >= 0x2060 && code <= 0x2064) return true // word joiner, invisible operators
  if (code >= 0x206a && code <= 0x206f) return true // deprecated format characters
  if (code === 0xfeff) return true // a byte order mark found mid-file
  return false
}

/**
 * Decodes bytes to text, honouring a byte order mark when there is one.
 *
 * UTF-8 is the assumption. UTF-16 is handled because Windows text editors
 * still produce it and a brief typed in Notepad is a real submission. There is
 * deliberately no fallback to a single-byte encoding: guessing Latin-1 for
 * what is really UTF-8 turns Arabic into mojibake, and handing the model
 * confident nonsense is worse than telling it the file could not be read.
 */
function decode(bytes: Uint8Array): string {
  if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) {
    return new TextDecoder('utf-16le', { fatal: true }).decode(bytes.subarray(2))
  }
  if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
    return new TextDecoder('utf-16be', { fatal: true }).decode(bytes.subarray(2))
  }
  const body =
    bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf
      ? bytes.subarray(3)
      : bytes
  return new TextDecoder('utf-8', { fatal: true }).decode(body)
}

/** Normalises line endings and drops what `isDropped` rejects. */
function clean(text: string): string {
  const out: string[] = []
  for (let i = 0; i < text.length; i += 1) {
    const code = text.charCodeAt(i)
    if (code === CARRIAGE_RETURN) {
      // A carriage return, alone or paired with a line feed, becomes one line.
      if (text.charCodeAt(i + 1) === LINE_FEED) i += 1
      out.push('\n')
      continue
    }
    if (isDropped(code)) continue
    out.push(text[i] as string)
  }
  return out.join('')
}

/**
 * Cuts to the ceiling, preferring a line boundary.
 *
 * Slicing mid-sentence invites the model to finish the thought itself. Ending
 * on a whole line makes the stop visible in the text, and the `truncated`
 * status says so outside the quoted block regardless.
 */
function cut(text: string): string {
  const hard = text.slice(0, MAX_EXTRACTED_CHARS)
  const lastBreak = hard.lastIndexOf('\n')
  // Only prefer the line boundary when it is not throwing away most of the
  // budget: one very long line has no useful break to fall back to.
  return lastBreak > MAX_EXTRACTED_CHARS * 0.8 ? hard.slice(0, lastBreak) : hard
}

export function extractText(bytes: Uint8Array, contentType: string): Extraction {
  if (!EXTRACTABLE_CONTENT_TYPES.includes(contentType)) return UNSUPPORTED

  let decoded: string
  try {
    decoded = decode(bytes)
  } catch {
    return failed('the bytes are not valid UTF-8 or UTF-16')
  }

  // A null character in something declared as text means the declaration is
  // wrong. Checked after decoding and before cleaning: ASCII encoded as UTF-16
  // is half null bytes, so the raw bytes cannot answer this, and `clean` would
  // drop the nulls and leave something that looks like real content.
  if (decoded.includes(NUL)) {
    return failed('the file is declared as text but contains null characters, so it is not text')
  }

  const cleaned = clean(decoded)
  if (cleaned.trim().length === 0) {
    return failed('the file has no readable text in it')
  }

  if (cleaned.length > MAX_EXTRACTED_CHARS) {
    return { status: 'truncated', text: cut(cleaned), reason: null }
  }
  return { status: 'extracted', text: cleaned, reason: null }
}

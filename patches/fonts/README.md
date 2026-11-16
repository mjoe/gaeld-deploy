# Local fonts

TrueType files named `patches/fonts/*.ttf` are converted for TCPDF during the image build, so that patches (for
example a custom invoice layout) can use them. The repository ships **no** fonts, and `*.ttf` files are ignored by git.
Never publish an image that contains a font you are not allowed to redistribute.

- The font name is derived from the file name in lower case without punctuation. `bold` becomes `b`, `italic` becomes
  `i` and `regular` is dropped: `AvenirNext-Regular.ttf` becomes `avenirnext`, `AvenirNext-Bold.ttf` becomes
  `avenirnextb`, `AvenirNext-DemiBold.ttf` becomes `avenirnextdemib`.
- Fonts from a `.ttc` collection must be extracted to single `.ttf` files first (for example with Python fontTools).
  The font must allow embedding (OS/2 `fsType` other than 2).

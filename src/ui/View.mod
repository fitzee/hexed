IMPLEMENTATION MODULE View;

FROM Gfx IMPORT Renderer;
FROM Font IMPORT FontHandle, TextWidth, LineSkip, DrawText;
FROM Canvas IMPORT SetColor, Clear, FillRect, SetBlendMode, BLEND_ALPHA, BLEND_NONE;
FROM Doc IMPORT Document, BytesPerRow, FileLen, GetByte, TotalRows,
                HasSelection, SelectionLow, SelectionHigh,
                IsDirty, NoSelection, ModeHex, ModeAscii, ModeBin;
FROM SearchState IMPORT IsSearchMode, GetSearchBuf, GetSearchLen,
                       GetSearchIsHex, SearchNotFound;
FROM GotoState IMPORT IsGotoMode, GetGotoBuf, GetGotoLen, GotoError;
FROM FillState IMPORT IsFillMode, GetFillBuf, GetFillLen;
FROM ReplaceState IMPORT IsReplaceMode, GetReplacePhase,
                         GetSearchBuf AS GetReplSearchBuf,
                         GetSearchLen AS GetReplSearchLen,
                         GetReplaceBuf AS GetReplReplaceBuf,
                         GetReplaceLen AS GetReplReplaceLen,
                         GetIsHex AS GetReplIsHex,
                         ReplaceNotFound,
                         PhaseSearch, PhaseReplace, PhaseConfirm;
FROM ExportState IMPORT IsExportMode, GetExportBuf, GetExportLen, ExportError;
FROM HistogramState IMPORT IsShowHistogram, GetFrequency, GetMaxFrequency,
                           GetTotalBytes;
FROM EndianState IMPORT IsLittleEndian;
FROM Theme IMPORT RGBA, Dark;

(* ── Pre-allocated formatting buffers ────────────────── *)
VAR
  hexBuf:  ARRAY [0..3] OF CHAR;
  addrBuf: ARRAY [0..17] OF CHAR;
  ascBuf:  ARRAY [0..1] OF CHAR;
  statBuf: ARRAY [0..511] OF CHAR;

(* ── Binary row hit test state ──────────────────────── *)
VAR
  binRowY, binRowX: INTEGER;
  binRowOk: BOOLEAN;
  binRowCellW: INTEGER;

(* ── Help panel wrapping state ─────────────────────── *)
VAR
  hpPadY, hpRowH, hpKeyW: INTEGER;
  hpMaxRows, hpColW, hpMaxX: INTEGER;

(* ── Hex formatting helpers (no allocation) ─────────── *)

CONST
  HexDigit = "0123456789ABCDEF";

PROCEDURE PowerOf16(n: INTEGER): CARDINAL;
VAR r: CARDINAL; i: INTEGER;
BEGIN
  r := 1;
  FOR i := 1 TO n DO r := r * 16; END;
  RETURN r;
END PowerOf16;

PROCEDURE FormatAddr(off: CARDINAL; nDigits: INTEGER);
VAR i: INTEGER;
    nibble: CARDINAL;
BEGIN
  FOR i := 0 TO nDigits - 1 DO
    nibble := (off DIV PowerOf16(nDigits - 1 - i)) MOD 16;
    addrBuf[i] := HexDigit[nibble];
  END;
  addrBuf[nDigits] := 0C;
END FormatAddr;

PROCEDURE FormatHexByte(val: CARDINAL);
BEGIN
  hexBuf[0] := HexDigit[val DIV 16];
  hexBuf[1] := HexDigit[val MOD 16];
  hexBuf[2] := 0C;
END FormatHexByte;

PROCEDURE IsPrintable(val: CARDINAL): BOOLEAN;
BEGIN
  RETURN (val >= 32) AND (val <= 126);
END IsPrintable;

(* ── Color helpers ───────────────────────────────────── *)

PROCEDURE SC(ren: Renderer; VAR c: RGBA);
BEGIN
  SetColor(ren, c.r, c.g, c.b, c.a);
END SC;

PROCEDURE DrawC(ren: Renderer; font: FontHandle; text: ARRAY OF CHAR;
                x, y: INTEGER; VAR c: RGBA);
BEGIN
  DrawText(ren, font, text, x, y, c.r, c.g, c.b, 255);
END DrawC;

(* ── Layout computation ─────────────────────────────── *)

PROCEDURE ComputeLayout(VAR v: ViewState; winW, winH: INTEGER);
VAR gap: INTEGER;
BEGIN
  v.layout.winW := winW;
  v.layout.winH := winH;
  v.layout.cellW := TextWidth(v.font, "M");
  v.layout.rowH := LineSkip(v.font);
  v.layout.padX := v.layout.cellW;
  v.layout.padY := v.layout.cellW DIV 2;

  v.layout.addrChars := 8;
  v.layout.addrColW := v.layout.addrChars * v.layout.cellW + v.layout.cellW;

  gap := v.layout.cellW;
  v.layout.hexColX := v.layout.padX + v.layout.addrColW + v.layout.cellW;
  v.layout.hexColW := BytesPerRow * 3 * v.layout.cellW + gap;

  v.layout.asciiColX := v.layout.hexColX + v.layout.hexColW + v.layout.cellW * 2;
  v.layout.asciiColW := BytesPerRow * v.layout.cellW;

  v.layout.statusH := v.layout.rowH + v.layout.padY;
  v.layout.statusY := winH - v.layout.statusH;

  v.layout.visRows := (v.layout.statusY - v.layout.padY) DIV v.layout.rowH;
  IF v.layout.visRows < 1 THEN v.layout.visRows := 1; END;

  v.layout.sbW := 10;
  v.layout.sbX := winW - v.layout.sbW;
END ComputeLayout;

(* ── Public ──────────────────────────────────────────── *)

PROCEDURE Init(VAR v: ViewState; f: FontHandle; winW, winH: INTEGER);
BEGIN
  v.font := f;
  ComputeLayout(v, winW, winH);
END Init;

PROCEDURE Resize(VAR v: ViewState; winW, winH: INTEGER);
BEGIN
  ComputeLayout(v, winW, winH);
END Resize;

(* ── Render ──────────────────────────────────────────── *)

PROCEDURE Render(VAR v: ViewState; ren: Renderer; VAR d: Document);
VAR
  row, col, visRow: INTEGER;
  off, fileSize: CARDINAL;
  byteVal: CARDINAL;
  x, y: INTEGER;
  selLo, selHi: CARDINAL;
  hasSel: BOOLEAN;
  isCursor: BOOLEAN;
  hexX, groupGap: INTEGER;
  totalR: CARDINAL;
  trackH, thumbH, thumbY: INTEGER;
BEGIN
  binRowOk := FALSE;
  fileSize := FileLen(d);
  hasSel := HasSelection(d);
  IF hasSel THEN
    selLo := SelectionLow(d);
    selHi := SelectionHigh(d);
  ELSE
    selLo := 0; selHi := 0;
  END;
  d.visibleRows := CARDINAL(v.layout.visRows);

  (* Clamp topRow after resize — prevent blank space at bottom *)
  totalR := TotalRows(d);
  IF totalR > d.visibleRows THEN
    IF d.topRow > totalR - d.visibleRows THEN
      d.topRow := totalR - d.visibleRows;
    END;
  ELSE
    d.topRow := 0;
  END;

  (* 1. Clear background *)
  SC(ren, Dark.bgPrimary);
  Clear(ren);

  (* 2. Alternating row backgrounds *)
  FOR visRow := 0 TO v.layout.visRows - 1 DO
    row := INTEGER(d.topRow) + visRow;
    IF CARDINAL(row) >= TotalRows(d) THEN
      visRow := v.layout.visRows;
    ELSE
      IF (row MOD 2) = 1 THEN
        y := v.layout.padY + visRow * v.layout.rowH;
        SC(ren, Dark.bgAlt);
        FillRect(ren, 0, y, v.layout.winW, v.layout.rowH);
      END;
    END;
  END;

  (* 3. Selection backgrounds *)
  IF hasSel THEN
    SetBlendMode(ren, BLEND_ALPHA);
    FOR visRow := 0 TO v.layout.visRows - 1 DO
      row := INTEGER(d.topRow) + visRow;
      IF CARDINAL(row) >= TotalRows(d) THEN
        visRow := v.layout.visRows;
      ELSE
        FOR col := 0 TO BytesPerRow - 1 DO
          off := CARDINAL(row) * BytesPerRow + CARDINAL(col);
          IF (off >= selLo) AND (off <= selHi) AND (off < fileSize) THEN
            y := v.layout.padY + visRow * v.layout.rowH;
            groupGap := 0;
            IF col >= 8 THEN groupGap := v.layout.cellW; END;
            hexX := v.layout.hexColX + col * 3 * v.layout.cellW + groupGap;
            SC(ren, Dark.selectionBg);
            FillRect(ren, hexX, y, v.layout.cellW * 2, v.layout.rowH);
            x := v.layout.asciiColX + col * v.layout.cellW;
            FillRect(ren, x, y, v.layout.cellW, v.layout.rowH);
          END;
        END;
      END;
    END;
    SetBlendMode(ren, BLEND_NONE);
  END;

  (* 4. Draw rows: address, hex, ASCII *)
  FOR visRow := 0 TO v.layout.visRows - 1 DO
    row := INTEGER(d.topRow) + visRow;
    IF CARDINAL(row) >= TotalRows(d) THEN
      visRow := v.layout.visRows;
    ELSE
      y := v.layout.padY + visRow * v.layout.rowH;

      (* Address column *)
      FormatAddr(CARDINAL(row) * BytesPerRow, v.layout.addrChars);
      DrawC(ren, v.font, addrBuf, v.layout.padX, y, Dark.fgOffset);

      (* Hex + ASCII bytes *)
      FOR col := 0 TO BytesPerRow - 1 DO
        off := CARDINAL(row) * BytesPerRow + CARDINAL(col);
        IF off < fileSize THEN
          byteVal := GetByte(d, off);
          isCursor := (off = d.cursor);

          groupGap := 0;
          IF col >= 8 THEN groupGap := v.layout.cellW; END;
          hexX := v.layout.hexColX + col * 3 * v.layout.cellW + groupGap;

          (* Cursor block *)
          IF isCursor THEN
            IF d.editMode = ModeBin THEN
              (* Dim highlight on hex cell to show active byte *)
              SetBlendMode(ren, BLEND_ALPHA);
              SC(ren, Dark.selectionBg);
              FillRect(ren, hexX, y, v.layout.cellW * 2, v.layout.rowH);
              SetBlendMode(ren, BLEND_NONE);
            ELSIF d.editMode = ModeHex THEN
              SC(ren, Dark.cursorBg);
              FillRect(ren, hexX, y, v.layout.cellW * 2, v.layout.rowH);
            ELSE
              SC(ren, Dark.cursorBg);
              x := v.layout.asciiColX + col * v.layout.cellW;
              FillRect(ren, x, y, v.layout.cellW, v.layout.rowH);
            END;
          END;

          (* Hex text *)
          FormatHexByte(byteVal);
          IF isCursor AND (d.editMode = ModeHex) THEN
            DrawC(ren, v.font, hexBuf, hexX, y, Dark.cursorFg);
          ELSE
            DrawC(ren, v.font, hexBuf, hexX, y, Dark.fgHex);
          END;

          (* ASCII text *)
          x := v.layout.asciiColX + col * v.layout.cellW;
          IF IsPrintable(byteVal) THEN
            ascBuf[0] := CHR(byteVal);
            ascBuf[1] := 0C;
            IF isCursor AND (d.editMode = ModeAscii) THEN
              DrawC(ren, v.font, ascBuf, x, y, Dark.cursorFg);
            ELSE
              DrawC(ren, v.font, ascBuf, x, y, Dark.fgAscii);
            END;
          ELSE
            ascBuf[0] := ".";
            ascBuf[1] := 0C;
            DrawC(ren, v.font, ascBuf, x, y, Dark.fgNonPrint);
          END;
        END;
      END;
    END;
  END;

  (* 5. Separator lines *)
  SC(ren, Dark.separator);
  FillRect(ren, v.layout.hexColX - v.layout.cellW DIV 2, v.layout.padY,
           1, v.layout.statusY - v.layout.padY);
  FillRect(ren, v.layout.asciiColX - v.layout.cellW, v.layout.padY,
           1, v.layout.statusY - v.layout.padY);

  (* 6. Status bar *)
  SC(ren, Dark.bgStatusBar);
  FillRect(ren, 0, v.layout.statusY, v.layout.winW, v.layout.statusH);
  SC(ren, Dark.separator);
  FillRect(ren, 0, v.layout.statusY, v.layout.winW, 1);

  RenderStatusBar(v, ren, d);

  (* 7. Side panel: histogram or help+inspector *)
  IF IsShowHistogram() THEN
    RenderHistogramPanel(v, ren, d);
  ELSE
    RenderHelpPanel(v, ren, d);
  END;

  (* 8. Vertical scrollbar *)
  IF totalR > CARDINAL(v.layout.visRows) THEN
    trackH := v.layout.statusY - v.layout.padY;
    SC(ren, Dark.sbTrack);
    FillRect(ren, v.layout.sbX, v.layout.padY, v.layout.sbW, trackH);
    thumbH := INTEGER(CARDINAL(v.layout.visRows) * CARDINAL(trackH) DIV totalR);
    IF thumbH < 20 THEN thumbH := 20; END;
    IF totalR > CARDINAL(trackH) THEN
      thumbY := v.layout.padY + INTEGER(d.topRow DIV (totalR DIV CARDINAL(trackH)));
    ELSE
      thumbY := v.layout.padY + INTEGER(d.topRow * CARDINAL(trackH) DIV totalR);
    END;
    IF thumbY + thumbH > v.layout.statusY THEN
      thumbY := v.layout.statusY - thumbH;
    END;
    SC(ren, Dark.sbThumb);
    FillRect(ren, v.layout.sbX, thumbY, v.layout.sbW, thumbH);
  END;
END Render;

(* ── Status bar ──────────────────────────────────────── *)

PROCEDURE AppendStr(VAR dst: ARRAY OF CHAR; VAR pos: INTEGER; src: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i <= INTEGER(HIGH(src))) AND (src[i] # 0C) AND (pos < INTEGER(HIGH(dst))) DO
    dst[pos] := src[i];
    INC(pos);
    INC(i);
  END;
  IF pos <= INTEGER(HIGH(dst)) THEN dst[pos] := 0C; END;
END AppendStr;

PROCEDURE AppendHexVal(VAR dst: ARRAY OF CHAR; VAR pos: INTEGER; val: CARDINAL; nDigits: INTEGER);
VAR i: INTEGER;
    nibble: CARDINAL;
BEGIN
  FOR i := 0 TO nDigits - 1 DO
    nibble := (val DIV PowerOf16(nDigits - 1 - i)) MOD 16;
    IF pos <= INTEGER(HIGH(dst)) THEN
      dst[pos] := HexDigit[nibble];
      INC(pos);
    END;
  END;
  IF pos <= INTEGER(HIGH(dst)) THEN dst[pos] := 0C; END;
END AppendHexVal;

PROCEDURE AppendDecVal(VAR dst: ARRAY OF CHAR; VAR pos: INTEGER; val: CARDINAL);
VAR digits: ARRAY [0..11] OF CHAR;
    i, n: INTEGER;
    v: CARDINAL;
BEGIN
  IF val = 0 THEN
    IF pos <= INTEGER(HIGH(dst)) THEN dst[pos] := "0"; INC(pos); END;
    IF pos <= INTEGER(HIGH(dst)) THEN dst[pos] := 0C; END;
    RETURN;
  END;
  v := val;
  n := 0;
  WHILE v > 0 DO
    digits[n] := CHR(ORD("0") + (v MOD 10));
    v := v DIV 10;
    INC(n);
  END;
  FOR i := n - 1 TO 0 BY -1 DO
    IF pos <= INTEGER(HIGH(dst)) THEN
      dst[pos] := digits[i];
      INC(pos);
    END;
  END;
  IF pos <= INTEGER(HIGH(dst)) THEN dst[pos] := 0C; END;
END AppendDecVal;

PROCEDURE AppendOctVal(VAR dst: ARRAY OF CHAR; VAR pos: INTEGER; val: CARDINAL);
VAR d2, d1, d0: CARDINAL;
BEGIN
  d2 := val DIV 64;
  d1 := (val DIV 8) MOD 8;
  d0 := val MOD 8;
  IF pos <= INTEGER(HIGH(dst)) THEN dst[pos] := CHR(ORD("0") + d2); INC(pos); END;
  IF pos <= INTEGER(HIGH(dst)) THEN dst[pos] := CHR(ORD("0") + d1); INC(pos); END;
  IF pos <= INTEGER(HIGH(dst)) THEN dst[pos] := CHR(ORD("0") + d0); INC(pos); END;
  IF pos <= INTEGER(HIGH(dst)) THEN dst[pos] := 0C; END;
END AppendOctVal;

PROCEDURE AppendBinVal(VAR dst: ARRAY OF CHAR; VAR pos: INTEGER; val: CARDINAL);
VAR i: INTEGER;
    pw, bit: CARDINAL;
BEGIN
  pw := 128;
  FOR i := 0 TO 7 DO
    bit := (val DIV pw) MOD 2;
    IF pos <= INTEGER(HIGH(dst)) THEN
      dst[pos] := CHR(ORD("0") + bit);
      INC(pos);
    END;
    IF pw > 1 THEN pw := pw DIV 2; END;
  END;
  IF pos <= INTEGER(HIGH(dst)) THEN dst[pos] := 0C; END;
END AppendBinVal;

PROCEDURE AppendSignedDec(VAR dst: ARRAY OF CHAR; VAR pos: INTEGER;
                          val: CARDINAL; bits: INTEGER);
VAR signBit, maxVal: CARDINAL;
    sval: INTEGER;
    uval: CARDINAL;
    digits: ARRAY [0..11] OF CHAR;
    i, n: INTEGER;
BEGIN
  (* Compute sign bit threshold *)
  IF bits = 8 THEN
    signBit := 128;
    maxVal := 256;
  ELSIF bits = 16 THEN
    signBit := 32768;
    maxVal := 65536;
  ELSE
    signBit := 2147483648;
    maxVal := 0;  (* special case for 32-bit *)
  END;
  IF val >= signBit THEN
    (* Negative *)
    IF pos <= INTEGER(HIGH(dst)) THEN dst[pos] := "-"; INC(pos); END;
    IF bits = 32 THEN
      (* For 32-bit: compute magnitude as maxUnsigned - val + 1 *)
      (* val is already the unsigned representation *)
      (* magnitude = 2^32 - val, but we can't hold 2^32 in CARDINAL on some systems *)
      (* Use: magnitude = (MAX(CARDINAL) - val) + 1 if MAX(CARDINAL) = 2^32-1 *)
      uval := MAX(CARDINAL) - val + 1;
    ELSE
      uval := maxVal - val;
    END;
    AppendDecVal(dst, pos, uval);
  ELSE
    AppendDecVal(dst, pos, val);
  END;
END AppendSignedDec;

PROCEDURE RenderSearchBar(VAR v: ViewState; ren: Renderer);
VAR
  pos: INTEGER;
  sx, sy: INTEGER;
  sBuf: ARRAY [0..127] OF CHAR;
BEGIN
  pos := 0;
  AppendStr(statBuf, pos, " Search (");
  IF GetSearchIsHex() THEN
    AppendStr(statBuf, pos, "hex");
  ELSE
    AppendStr(statBuf, pos, "ascii");
  END;
  AppendStr(statBuf, pos, "): ");

  GetSearchBuf(sBuf);
  AppendStr(statBuf, pos, sBuf);
  AppendStr(statBuf, pos, "_");

  IF SearchNotFound() THEN
    AppendStr(statBuf, pos, "  -- Not found");
  END;

  sx := v.layout.padX;
  sy := v.layout.statusY + v.layout.padY DIV 2;
  DrawC(ren, v.font, statBuf, sx, sy, Dark.fgStatus);
END RenderSearchBar;

PROCEDURE RenderGotoBar(VAR v: ViewState; ren: Renderer);
VAR
  pos: INTEGER;
  sx, sy: INTEGER;
  gBuf: ARRAY [0..31] OF CHAR;
BEGIN
  pos := 0;
  AppendStr(statBuf, pos, " Go to: 0x");

  GetGotoBuf(gBuf);
  AppendStr(statBuf, pos, gBuf);
  AppendStr(statBuf, pos, "_");

  IF GotoError() THEN
    AppendStr(statBuf, pos, "  -- Invalid");
  END;

  sx := v.layout.padX;
  sy := v.layout.statusY + v.layout.padY DIV 2;
  DrawC(ren, v.font, statBuf, sx, sy, Dark.fgStatus);
END RenderGotoBar;

PROCEDURE RenderFillBar(VAR v: ViewState; ren: Renderer);
VAR
  pos: INTEGER;
  sx, sy: INTEGER;
  fBuf: ARRAY [0..3] OF CHAR;
BEGIN
  pos := 0;
  AppendStr(statBuf, pos, " Fill (hex byte): ");

  GetFillBuf(fBuf);
  AppendStr(statBuf, pos, fBuf);
  AppendStr(statBuf, pos, "_");

  sx := v.layout.padX;
  sy := v.layout.statusY + v.layout.padY DIV 2;
  DrawC(ren, v.font, statBuf, sx, sy, Dark.fgStatus);
END RenderFillBar;

PROCEDURE RenderReplaceBar(VAR v: ViewState; ren: Renderer);
VAR
  pos: INTEGER;
  sx, sy: INTEGER;
  rBuf: ARRAY [0..127] OF CHAR;
  phase: INTEGER;
BEGIN
  pos := 0;
  (* Determine phase as integer *)
  IF GetReplacePhase() = PhaseSearch THEN
    phase := 0;
  ELSIF GetReplacePhase() = PhaseReplace THEN
    phase := 1;
  ELSE
    phase := 2;
  END;

  IF phase = 0 THEN
    AppendStr(statBuf, pos, " Replace search (");
    IF GetReplIsHex() THEN
      AppendStr(statBuf, pos, "hex");
    ELSE
      AppendStr(statBuf, pos, "ascii");
    END;
    AppendStr(statBuf, pos, "): ");
    GetReplSearchBuf(rBuf);
    AppendStr(statBuf, pos, rBuf);
    AppendStr(statBuf, pos, "_");
    IF ReplaceNotFound() THEN
      AppendStr(statBuf, pos, "  -- Not found");
    END;
  ELSIF phase = 1 THEN
    AppendStr(statBuf, pos, " Replace with (");
    IF GetReplIsHex() THEN
      AppendStr(statBuf, pos, "hex");
    ELSE
      AppendStr(statBuf, pos, "ascii");
    END;
    AppendStr(statBuf, pos, "): ");
    GetReplReplaceBuf(rBuf);
    AppendStr(statBuf, pos, rBuf);
    AppendStr(statBuf, pos, "_");
  ELSE
    AppendStr(statBuf, pos, " Replace? [Y]es [N]ext [A]ll [Esc]");
  END;

  sx := v.layout.padX;
  sy := v.layout.statusY + v.layout.padY DIV 2;
  DrawC(ren, v.font, statBuf, sx, sy, Dark.fgStatus);
END RenderReplaceBar;

PROCEDURE RenderExportBar(VAR v: ViewState; ren: Renderer);
VAR
  pos: INTEGER;
  sx, sy: INTEGER;
  eBuf: ARRAY [0..255] OF CHAR;
BEGIN
  pos := 0;
  AppendStr(statBuf, pos, " Export to: ");

  GetExportBuf(eBuf);
  AppendStr(statBuf, pos, eBuf);
  AppendStr(statBuf, pos, "_");

  IF ExportError() THEN
    AppendStr(statBuf, pos, "  -- Write error");
  END;

  sx := v.layout.padX;
  sy := v.layout.statusY + v.layout.padY DIV 2;
  DrawC(ren, v.font, statBuf, sx, sy, Dark.fgStatus);
END RenderExportBar;

PROCEDURE RenderStatusBar(VAR v: ViewState; ren: Renderer; VAR d: Document);
VAR
  pos: INTEGER;
  byteVal, fileSize: CARDINAL;
  selCount, selOff: CARDINAL;
  sx, sy: INTEGER;
BEGIN
  IF IsFillMode() THEN
    RenderFillBar(v, ren);
    RETURN;
  END;

  IF IsGotoMode() THEN
    RenderGotoBar(v, ren);
    RETURN;
  END;

  IF IsSearchMode() THEN
    RenderSearchBar(v, ren);
    RETURN;
  END;

  IF IsReplaceMode() THEN
    RenderReplaceBar(v, ren);
    RETURN;
  END;

  IF IsExportMode() THEN
    RenderExportBar(v, ren);
    RETURN;
  END;

  pos := 0;
  fileSize := FileLen(d);

  IF HasSelection(d) THEN
    selOff := SelectionLow(d);
    selCount := SelectionHigh(d) - selOff + 1;
    AppendStr(statBuf, pos, " 0x");
    AppendHexVal(statBuf, pos, selCount, 8);
    AppendStr(statBuf, pos, " bytes selected at offset 0x");
    AppendHexVal(statBuf, pos, selOff, 8);
    AppendStr(statBuf, pos, " out of 0x");
    AppendHexVal(statBuf, pos, fileSize, 8);
    AppendStr(statBuf, pos, " bytes");
    sx := v.layout.padX;
    sy := v.layout.statusY + v.layout.padY DIV 2;
    DrawC(ren, v.font, statBuf, sx, sy, Dark.fgStatus);
    RETURN;
  END;

  AppendStr(statBuf, pos, " ");
  AppendStr(statBuf, pos, d.fileName);
  AppendStr(statBuf, pos, "  |  ");
  AppendDecVal(statBuf, pos, fileSize);
  AppendStr(statBuf, pos, " bytes");
  AppendStr(statBuf, pos, "  |  0x");
  AppendHexVal(statBuf, pos, d.cursor, 8);
  AppendStr(statBuf, pos, " (");
  AppendDecVal(statBuf, pos, d.cursor);
  AppendStr(statBuf, pos, ")");

  IF d.cursor < fileSize THEN
    byteVal := GetByte(d, d.cursor);
    AppendStr(statBuf, pos, "  |  0x");
    AppendHexVal(statBuf, pos, byteVal, 2);
    AppendStr(statBuf, pos, " (");
    AppendDecVal(statBuf, pos, byteVal);
    AppendStr(statBuf, pos, ")");
  END;

  IF d.editMode = ModeHex THEN
    AppendStr(statBuf, pos, "  |  HEX");
  ELSIF d.editMode = ModeAscii THEN
    AppendStr(statBuf, pos, "  |  ASCII");
  ELSE
    AppendStr(statBuf, pos, "  |  BIN");
  END;

  IF IsLittleEndian() THEN
    AppendStr(statBuf, pos, "  |  LE");
  ELSE
    AppendStr(statBuf, pos, "  |  BE");
  END;

  IF IsDirty(d) THEN
    AppendStr(statBuf, pos, "  |  MODIFIED");
  END;

  sx := v.layout.padX;
  sy := v.layout.statusY + v.layout.padY DIV 2;
  DrawC(ren, v.font, statBuf, sx, sy, Dark.fgStatus);
END RenderStatusBar;

(* ── Help panel ──────────────────────────────────────── *)

PROCEDURE HelpLine(ren: Renderer; font: FontHandle;
                   x, y, keyW: INTEGER; key, desc: ARRAY OF CHAR);
BEGIN
  DrawC(ren, font, key, x, y, Dark.helpKey);
  DrawC(ren, font, desc, x + keyW, y, Dark.helpDesc);
END HelpLine;

(* ── Help panel wrapping helpers ───────────────────── *)

PROCEDURE HPCheck(VAR hx, row: INTEGER): BOOLEAN;
BEGIN
  IF row >= hpMaxRows THEN
    row := 0;
    INC(hx, hpColW);
    IF hx + hpColW > hpMaxX THEN RETURN FALSE; END;
  END;
  RETURN TRUE;
END HPCheck;

PROCEDURE HP(ren: Renderer; font: FontHandle;
             VAR hx, row: INTEGER;
             key, desc: ARRAY OF CHAR): BOOLEAN;
VAR y: INTEGER;
BEGIN
  IF NOT HPCheck(hx, row) THEN RETURN FALSE; END;
  y := hpPadY + row * hpRowH;
  HelpLine(ren, font, hx, y, hpKeyW, key, desc);
  INC(row);
  RETURN TRUE;
END HP;

PROCEDURE HPHead(ren: Renderer; font: FontHandle;
                 VAR hx, row: INTEGER;
                 title: ARRAY OF CHAR): BOOLEAN;
VAR y: INTEGER;
BEGIN
  IF row > 0 THEN INC(row); END;
  IF row + 3 > hpMaxRows THEN
    row := 0;
    INC(hx, hpColW);
    IF hx + hpColW > hpMaxX THEN RETURN FALSE; END;
  END;
  y := hpPadY + row * hpRowH;
  DrawC(ren, font, title, hx, y, Dark.helpHeader);
  INC(row, 2);
  RETURN TRUE;
END HPHead;

(* ── Data Inspector ─────────────────────────────────── *)

PROCEDURE RenderInspector(VAR v: ViewState; ren: Renderer; VAR d: Document;
                          VAR helpX: INTEGER; VAR row: INTEGER);
VAR
  y: INTEGER;
  pos: INTEGER;
  b0, b1, b2, b3: CARDINAL;
  fileSize: CARDINAL;
  val16, val32: CARDINAL;
  bitI: INTEGER;
  pw, bitVal: CARDINAL;
  bitBuf: ARRAY [0..1] OF CHAR;
  bx: INTEGER;
BEGIN
  fileSize := FileLen(d);
  IF (fileSize = 0) OR (d.cursor >= fileSize) THEN RETURN; END;

  b0 := GetByte(d, d.cursor);

  IF IsLittleEndian() THEN
    IF NOT HPHead(ren, v.font, helpX, row, "INSPECTOR (LE)") THEN RETURN; END;
  ELSE
    IF NOT HPHead(ren, v.font, helpX, row, "INSPECTOR (BE)") THEN RETURN; END;
  END;

  (* Hex *)
  pos := 0;
  AppendStr(statBuf, pos, "0x");
  AppendHexVal(statBuf, pos, b0, 2);
  IF NOT HP(ren, v.font, helpX, row, "Hex", statBuf) THEN RETURN; END;

  (* Decimal *)
  pos := 0;
  AppendDecVal(statBuf, pos, b0);
  IF NOT HP(ren, v.font, helpX, row, "Dec", statBuf) THEN RETURN; END;

  (* Octal *)
  pos := 0;
  AppendOctVal(statBuf, pos, b0);
  IF NOT HP(ren, v.font, helpX, row, "Oct", statBuf) THEN RETURN; END;

  (* Binary — per-bit rendering with cursor highlight in ModeBin *)
  IF NOT HPCheck(helpX, row) THEN RETURN; END;
  y := hpPadY + row * hpRowH;
  DrawC(ren, v.font, "Bin", helpX, y, Dark.helpKey);
  bx := helpX + hpKeyW;
  binRowX := bx;
  binRowY := y;
  binRowCellW := v.layout.cellW;
  binRowOk := TRUE;
  pw := 128;
  bitBuf[1] := 0C;
  FOR bitI := 0 TO 7 DO
    bitVal := (b0 DIV pw) MOD 2;
    bitBuf[0] := CHR(ORD("0") + bitVal);
    IF (d.editMode = ModeBin) AND (CARDINAL(bitI) = d.binBitPos) THEN
      SC(ren, Dark.cursorBg);
      FillRect(ren, bx, y, v.layout.cellW, v.layout.rowH);
      DrawC(ren, v.font, bitBuf, bx, y, Dark.cursorFg);
    ELSE
      DrawC(ren, v.font, bitBuf, bx, y, Dark.helpDesc);
    END;
    INC(bx, v.layout.cellW);
    IF pw > 1 THEN pw := pw DIV 2; END;
  END;
  INC(row);

  (* Int8 signed / unsigned *)
  pos := 0;
  AppendSignedDec(statBuf, pos, b0, 8);
  AppendStr(statBuf, pos, " / ");
  AppendDecVal(statBuf, pos, b0);
  IF NOT HP(ren, v.font, helpX, row, "Int8", statBuf) THEN RETURN; END;

  (* Int16 — endian-aware *)
  IF d.cursor + 1 < fileSize THEN
    b1 := GetByte(d, d.cursor + 1);
    IF IsLittleEndian() THEN
      val16 := b0 + b1 * 256;
    ELSE
      val16 := b0 * 256 + b1;
    END;
    pos := 0;
    AppendSignedDec(statBuf, pos, val16, 16);
    AppendStr(statBuf, pos, " / ");
    AppendDecVal(statBuf, pos, val16);
    IF NOT HP(ren, v.font, helpX, row, "Int16", statBuf) THEN RETURN; END;
  ELSE
    IF NOT HP(ren, v.font, helpX, row, "Int16", "—") THEN RETURN; END;
  END;

  (* Int32 — endian-aware *)
  IF d.cursor + 3 < fileSize THEN
    b1 := GetByte(d, d.cursor + 1);
    b2 := GetByte(d, d.cursor + 2);
    b3 := GetByte(d, d.cursor + 3);
    IF IsLittleEndian() THEN
      val32 := b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
    ELSE
      val32 := b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
    END;
    pos := 0;
    AppendSignedDec(statBuf, pos, val32, 32);
    AppendStr(statBuf, pos, " / ");
    AppendDecVal(statBuf, pos, val32);
    IF NOT HP(ren, v.font, helpX, row, "Int32", statBuf) THEN RETURN; END;
  ELSE
    IF NOT HP(ren, v.font, helpX, row, "Int32", "—") THEN RETURN; END;
  END;

  (* ASCII *)
  pos := 0;
  IF IsPrintable(b0) THEN
    AppendStr(statBuf, pos, "'");
    statBuf[pos] := CHR(b0); INC(pos);
    statBuf[pos] := 0C;
    AppendStr(statBuf, pos, "'");
  ELSE
    AppendStr(statBuf, pos, "n/p");
  END;
  IF NOT HP(ren, v.font, helpX, row, "ASCII", statBuf) THEN RETURN; END;
END RenderInspector;

(* ── Help + Inspector panel ─────────────────────────── *)

PROCEDURE RenderHelpPanel(VAR v: ViewState; ren: Renderer; VAR d: Document);
VAR
  helpX, row: INTEGER;
  minW: INTEGER;
BEGIN
  helpX := v.layout.asciiColX + v.layout.asciiColW + v.layout.cellW * 2;
  minW := helpX + v.layout.cellW * 19;
  IF minW > v.layout.winW THEN RETURN; END;

  (* Set up wrapping state *)
  hpKeyW := v.layout.cellW * 7;
  hpPadY := v.layout.padY;
  hpRowH := v.layout.rowH;
  hpMaxRows := v.layout.visRows;
  hpColW := v.layout.cellW * 19;
  hpMaxX := v.layout.sbX;

  (* Separator *)
  SC(ren, Dark.separator);
  FillRect(ren, helpX - v.layout.cellW, v.layout.padY,
           1, v.layout.statusY - v.layout.padY);

  row := 0;
  IF NOT HPHead(ren, v.font, helpX, row, "NAVIGATION") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "Up/Dn", "Move row") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "Lt/Rt", "Move byte") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "PgUp", "Page up") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "PgDn", "Page down") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "Home", "Row start") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "End", "Row end") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘Up", "File start") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘Down", "File end") THEN RETURN; END;

  IF NOT HPHead(ren, v.font, helpX, row, "EDITING") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "Tab", "Hex/ASCII") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "0-F", "Hex input") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "Type", "ASCII input") THEN RETURN; END;

  IF NOT HPHead(ren, v.font, helpX, row, "COMMANDS") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘S", "Save") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘Z", "Undo") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘Y", "Redo") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘+", "Zoom in") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘-", "Zoom out") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘F", "Search") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘G", "Find next") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘R", "Replace") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘L", "Go to") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘C", "Copy") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘V", "Paste") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘E", "Fill") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘D", "Export") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘B", "Histogram") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘T", "Endian") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "⌘I", "About") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "Esc", "Deselect") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "Drag", "Select") THEN RETURN; END;
  IF NOT HP(ren, v.font, helpX, row, "Wheel", "Scroll") THEN RETURN; END;

  RenderInspector(v, ren, d, helpX, row);
END RenderHelpPanel;

(* ── Histogram panel ────────────────────────────────── *)

PROCEDURE ComputeBarColor(fraction: INTEGER; VAR r, g, b: INTEGER);
(* 5-stop color ramp: blue → cyan → green → yellow → red
   fraction is 0..100 *)
VAR seg, t: INTEGER;
BEGIN
  IF fraction < 0 THEN fraction := 0; END;
  IF fraction > 100 THEN fraction := 100; END;

  seg := fraction DIV 25;   (* 0..4, but clamp to 3 max for 4 segments *)
  t := (fraction MOD 25) * 4;  (* 0..96 within segment, scaled ~0..100 *)
  IF seg > 3 THEN seg := 3; t := 100; END;

  IF seg = 0 THEN
    (* blue → cyan: R=30, G 80→220, B=230 *)
    r := 30;
    g := 80 + (220 - 80) * t DIV 100;
    b := 230;
  ELSIF seg = 1 THEN
    (* cyan → green: R=30, G=220, B 230→60 *)
    r := 30;
    g := 220;
    b := 230 - (230 - 60) * t DIV 100;
  ELSIF seg = 2 THEN
    (* green → yellow: R 30→230, G=220, B=60 *)
    r := 30 + (230 - 30) * t DIV 100;
    g := 220;
    b := 60;
  ELSE
    (* yellow → red: R=230, G 220→50, B=60 *)
    r := 230;
    g := 220 - (220 - 50) * t DIV 100;
    b := 60;
  END;
END ComputeBarColor;

PROCEDURE RenderHistogramPanel(VAR v: ViewState; ren: Renderer; VAR d: Document);
VAR
  helpX, y, row: INTEGER;
  minW, keyW: INTEGER;
  maxBarW: INTEGER;
  i: CARDINAL;
  count, maxF, total: CARDINAL;
  barW, fraction: INTEGER;
  cr, cg, cb: INTEGER;
  pos: INTEGER;
  curByte: CARDINAL;
  fileSize: CARDINAL;
  pct, frac: CARDINAL;
  availH, barH: INTEGER;
BEGIN
  helpX := v.layout.asciiColX + v.layout.asciiColW + v.layout.cellW * 2;
  minW := helpX + v.layout.cellW * 22;
  IF minW > v.layout.winW THEN RETURN; END;
  keyW := v.layout.cellW * 7;
  maxBarW := v.layout.winW - helpX - keyW - v.layout.cellW;

  (* Separator *)
  SC(ren, Dark.separator);
  FillRect(ren, helpX - v.layout.cellW, v.layout.padY,
           1, v.layout.statusY - v.layout.padY);

  maxF := GetMaxFrequency();
  total := GetTotalBytes();

  row := 0;
  y := v.layout.padY + row * v.layout.rowH;
  DrawC(ren, v.font, "BYTE FREQUENCY", helpX, y, Dark.helpHeader);
  INC(row, 2);

  (* Available height for 256 bars *)
  availH := v.layout.statusY - v.layout.padY - row * v.layout.rowH;
  IF availH < 256 THEN
    barH := 1;
  ELSE
    barH := availH DIV 256;
    IF barH < 1 THEN barH := 1; END;
  END;

  IF maxBarW < 1 THEN maxBarW := 1; END;

  (* Determine cursor byte for highlight *)
  fileSize := FileLen(d);
  curByte := 256;  (* sentinel: no highlight *)
  IF (fileSize > 0) AND (d.cursor < fileSize) THEN
    curByte := GetByte(d, d.cursor);
  END;

  FOR i := 0 TO 255 DO
    count := GetFrequency(i);
    y := v.layout.padY + row * v.layout.rowH + INTEGER(i) * barH;
    IF y + barH > v.layout.statusY THEN
      i := 256;  (* break *)
    ELSE
      (* Highlight strip for cursor byte *)
      IF i = curByte THEN
        SetBlendMode(ren, BLEND_ALPHA);
        SC(ren, Dark.selectionBg);
        FillRect(ren, helpX, y, maxBarW, barH);
        SetBlendMode(ren, BLEND_NONE);
      END;
      IF (count > 0) AND (maxF > 0) THEN
        barW := INTEGER(count) * maxBarW DIV INTEGER(maxF);
        IF barW < 1 THEN barW := 1; END;
        fraction := INTEGER(count) * 100 DIV INTEGER(maxF);
        ComputeBarColor(fraction, cr, cg, cb);
        SetColor(ren, cr, cg, cb, 255);
        FillRect(ren, helpX, y, barW, barH);
      END;
      (* Draw hex label on highlighted row *)
      IF i = curByte THEN
        pos := 0;
        AppendStr(statBuf, pos, "0x");
        AppendHexVal(statBuf, pos, i, 2);
        DrawC(ren, v.font, statBuf, helpX + maxBarW + v.layout.cellW DIV 2, y,
              Dark.cursorFg);
      END;
    END;
  END;

  (* Footer: cursor byte frequency *)
  IF curByte <= 255 THEN
    count := GetFrequency(curByte);
    pos := 0;
    AppendStr(statBuf, pos, "0x");
    AppendHexVal(statBuf, pos, curByte, 2);
    AppendStr(statBuf, pos, ": ");
    AppendDecVal(statBuf, pos, count);
    IF total > 0 THEN
      pct := count * 10000 DIV total;
      frac := pct MOD 100;
      pct := pct DIV 100;
      AppendStr(statBuf, pos, " (");
      AppendDecVal(statBuf, pos, pct);
      statBuf[pos] := '.'; INC(pos);
      statBuf[pos] := CHR(ORD('0') + frac DIV 10); INC(pos);
      statBuf[pos] := CHR(ORD('0') + frac MOD 10); INC(pos);
      AppendStr(statBuf, pos, "%)");
    END;
    (* Place footer at bottom of histogram area *)
    y := v.layout.statusY - v.layout.rowH;
    DrawC(ren, v.font, statBuf, helpX, y, Dark.fgStatus);
  END;
END RenderHistogramPanel;

(* ── Hit testing ─────────────────────────────────────── *)

PROCEDURE HitTest(VAR v: ViewState; VAR d: Document;
                  mx, my: INTEGER; VAR offset: CARDINAL): BOOLEAN;
VAR
  visRow, col, groupGap, hexX: INTEGER;
  row: CARDINAL;
  fileSize: CARDINAL;
BEGIN
  fileSize := FileLen(d);
  IF fileSize = 0 THEN RETURN FALSE; END;
  IF (my < v.layout.padY) OR (my >= v.layout.statusY) THEN RETURN FALSE; END;

  visRow := (my - v.layout.padY) DIV v.layout.rowH;
  row := d.topRow + CARDINAL(visRow);

  IF (mx >= v.layout.hexColX) AND (mx < v.layout.asciiColX - v.layout.cellW) THEN
    FOR col := 0 TO BytesPerRow - 1 DO
      groupGap := 0;
      IF col >= 8 THEN groupGap := v.layout.cellW; END;
      hexX := v.layout.hexColX + col * 3 * v.layout.cellW + groupGap;
      IF (mx >= hexX) AND (mx < hexX + v.layout.cellW * 2) THEN
        offset := row * BytesPerRow + CARDINAL(col);
        IF offset < fileSize THEN RETURN TRUE; END;
      END;
    END;
  END;

  IF (mx >= v.layout.asciiColX) AND (mx < v.layout.asciiColX + v.layout.asciiColW) THEN
    col := (mx - v.layout.asciiColX) DIV v.layout.cellW;
    IF (col >= 0) AND (col < BytesPerRow) THEN
      offset := row * BytesPerRow + CARDINAL(col);
      IF offset < fileSize THEN RETURN TRUE; END;
    END;
  END;

  RETURN FALSE;
END HitTest;

PROCEDURE DragHitTest(VAR v: ViewState; VAR d: Document;
                      mx, my: INTEGER; VAR offset: CARDINAL): BOOLEAN;
VAR
  visRow, col: INTEGER;
  row, off, fileSize: CARDINAL;
  relX, group2X: INTEGER;
BEGIN
  fileSize := FileLen(d);
  IF fileSize = 0 THEN RETURN FALSE; END;

  (* Clamp Y to visible content area *)
  IF my < v.layout.padY THEN my := v.layout.padY; END;
  IF my >= v.layout.statusY THEN my := v.layout.statusY - 1; END;

  visRow := (my - v.layout.padY) DIV v.layout.rowH;
  row := d.topRow + CARDINAL(visRow);

  (* Determine column from X position *)
  col := -1;

  IF mx < v.layout.hexColX THEN
    (* Left of hex area — snap to column 0 *)
    col := 0;
  ELSIF mx < v.layout.asciiColX - v.layout.cellW THEN
    (* In hex area — snap to nearest column via division *)
    relX := mx - v.layout.hexColX;
    (* Second group (cols 8-15) starts after 8*3*cellW + cellW *)
    group2X := 8 * 3 * v.layout.cellW + v.layout.cellW;
    IF relX >= group2X THEN
      col := 8 + (relX - group2X) DIV (3 * v.layout.cellW);
    ELSE
      col := relX DIV (3 * v.layout.cellW);
    END;
  ELSIF mx < v.layout.asciiColX THEN
    (* Gap between hex and ASCII — snap to last hex column *)
    col := BytesPerRow - 1;
  ELSE
    (* ASCII area or right of it — snap to ASCII column *)
    col := (mx - v.layout.asciiColX) DIV v.layout.cellW;
  END;

  IF col < 0 THEN col := 0; END;
  IF col > BytesPerRow - 1 THEN col := BytesPerRow - 1; END;

  off := row * BytesPerRow + CARDINAL(col);
  IF off >= fileSize THEN off := fileSize - 1; END;
  offset := off;
  RETURN TRUE;
END DragHitTest;

PROCEDURE BinHitTest(VAR v: ViewState; VAR d: Document;
                     mx, my: INTEGER; VAR bitPos: CARDINAL): BOOLEAN;
VAR bit: INTEGER;
BEGIN
  IF NOT binRowOk THEN RETURN FALSE; END;
  IF (my < binRowY) OR (my >= binRowY + v.layout.rowH) THEN RETURN FALSE; END;
  IF (mx < binRowX) OR (binRowCellW = 0) THEN RETURN FALSE; END;
  bit := (mx - binRowX) DIV binRowCellW;
  IF (bit < 0) OR (bit > 7) THEN RETURN FALSE; END;
  bitPos := CARDINAL(bit);
  RETURN TRUE;
END BinHitTest;

PROCEDURE MinWindowSize(VAR v: ViewState; VAR minW, minH: INTEGER);
CONST MinRows = 4;
BEGIN
  (* Width: padX + addr + gap + hex grid + gap + ascii + scrollbar *)
  minW := v.layout.asciiColX + v.layout.asciiColW + v.layout.sbW;
  (* Height: padY + MinRows * rowH + statusH *)
  minH := v.layout.padY + MinRows * v.layout.rowH + v.layout.statusH;
END MinWindowSize;

END View.

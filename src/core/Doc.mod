IMPLEMENTATION MODULE Doc;

FROM SYSTEM IMPORT ADR;
FROM ByteStore IMPORT Open AS StoreOpen, Close AS StoreClose,
                      Len AS StoreLen, GetByte AS StoreGetByte,
                      SetByte AS StoreSetByte, IsDirty AS StoreIsDirty,
                      Flush AS StoreFlush, ReadBlock AS StoreReadBlock;
FROM Cmd IMPORT Init AS CmdInit, RecordSetByte,
                BeginGroup AS CmdBeginGroup, EndGroup AS CmdEndGroup,
                Undo AS CmdUndo, Redo AS CmdRedo;
FROM Sys IMPORT m2sys_basename, m2sys_file_size;

PROCEDURE CopyStr(VAR dst: ARRAY OF CHAR; src: ARRAY OF CHAR);
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE (i < HIGH(src)) AND (i < HIGH(dst)) AND (src[i] # 0C) DO
    dst[i] := src[i];
    INC(i);
  END;
  IF i <= HIGH(dst) THEN dst[i] := 0C; END;
END CopyStr;

PROCEDURE Open(VAR d: Document; path: ARRAY OF CHAR): BOOLEAN;
VAR sz64: LONGINT;
BEGIN
  (* Pre-check: reject files > 4GB (CARDINAL range) *)
  sz64 := m2sys_file_size(ADR(path));
  IF sz64 < 0 THEN RETURN FALSE; END;
  IF sz64 > LONGINT(MAX(CARDINAL)) THEN RETURN FALSE; END;

  d.cursor := 0;
  d.selAnchor := NoSelection;
  d.topRow := 0;
  d.nibblePhase := 0;
  d.binBitPos := 0;
  d.editMode := ModeHex;
  d.visibleRows := 30;
  CmdInit(d.history);
  m2sys_basename(ADR(path), ADR(d.fileName), 256);
  RETURN StoreOpen(d.store, path);
END Open;

PROCEDURE Close(VAR d: Document);
BEGIN
  StoreClose(d.store);
END Close;

PROCEDURE Save(VAR d: Document): BOOLEAN;
BEGIN
  RETURN StoreFlush(d.store);
END Save;

PROCEDURE FileLen(VAR d: Document): CARDINAL;
BEGIN
  RETURN StoreLen(d.store);
END FileLen;

PROCEDURE TotalRows(VAR d: Document): CARDINAL;
VAR len: CARDINAL;
BEGIN
  len := StoreLen(d.store);
  IF len = 0 THEN RETURN 1; END;
  RETURN (len + BytesPerRow - 1) DIV BytesPerRow;
END TotalRows;

PROCEDURE GetByte(VAR d: Document; off: CARDINAL): CARDINAL;
BEGIN
  RETURN StoreGetByte(d.store, off);
END GetByte;

PROCEDURE ReadBlock(VAR d: Document; off: CARDINAL;
                    VAR buf: ARRAY OF CHAR; maxLen: CARDINAL): CARDINAL;
BEGIN
  RETURN StoreReadBlock(d.store, off, buf, maxLen);
END ReadBlock;

PROCEDURE PutByte(VAR d: Document; off: CARDINAL; val: CARDINAL);
VAR oldVal: CARDINAL;
BEGIN
  oldVal := StoreGetByte(d.store, off);
  StoreSetByte(d.store, off, val);
  RecordSetByte(d.history, off, oldVal, val);
END PutByte;

PROCEDURE IsDirty(VAR d: Document): BOOLEAN;
BEGIN
  RETURN StoreIsDirty(d.store);
END IsDirty;

(* ── Cursor movement ────────────────────────────────── *)

PROCEDURE MoveCursorLeft(VAR d: Document);
BEGIN
  IF d.cursor > 0 THEN
    DEC(d.cursor);
    d.nibblePhase := 0;
    d.binBitPos := 0;
    EnsureVisible(d);
  END;
END MoveCursorLeft;

PROCEDURE MoveCursorRight(VAR d: Document);
VAR len: CARDINAL;
BEGIN
  len := StoreLen(d.store);
  IF len > 0 THEN
    IF d.cursor < len - 1 THEN
      INC(d.cursor);
      d.nibblePhase := 0;
      d.binBitPos := 0;
      EnsureVisible(d);
    END;
  END;
END MoveCursorRight;

PROCEDURE MoveCursorUp(VAR d: Document);
BEGIN
  IF d.cursor >= BytesPerRow THEN
    DEC(d.cursor, BytesPerRow);
    d.nibblePhase := 0;
    d.binBitPos := 0;
    EnsureVisible(d);
  END;
END MoveCursorUp;

PROCEDURE MoveCursorDown(VAR d: Document);
VAR len: CARDINAL;
BEGIN
  len := StoreLen(d.store);
  IF d.cursor + BytesPerRow < len THEN
    INC(d.cursor, BytesPerRow);
  ELSIF len > 0 THEN
    d.cursor := len - 1;
  END;
  d.nibblePhase := 0;
  d.binBitPos := 0;
  EnsureVisible(d);
END MoveCursorDown;

PROCEDURE PageUp(VAR d: Document);
VAR step: CARDINAL;
BEGIN
  step := d.visibleRows * BytesPerRow;
  IF d.cursor >= step THEN
    DEC(d.cursor, step);
  ELSE
    d.cursor := d.cursor MOD BytesPerRow;
  END;
  IF d.topRow >= d.visibleRows THEN
    DEC(d.topRow, d.visibleRows);
  ELSE
    d.topRow := 0;
  END;
  d.nibblePhase := 0;
  d.binBitPos := 0;
  EnsureVisible(d);
END PageUp;

PROCEDURE PageDown(VAR d: Document);
VAR step, len, total: CARDINAL;
BEGIN
  len := StoreLen(d.store);
  total := TotalRows(d);
  step := d.visibleRows * BytesPerRow;
  IF d.cursor + step < len THEN
    INC(d.cursor, step);
  ELSIF len > 0 THEN
    d.cursor := len - 1;
  END;
  INC(d.topRow, d.visibleRows);
  IF d.topRow + d.visibleRows > total THEN
    IF total > d.visibleRows THEN
      d.topRow := total - d.visibleRows;
    ELSE
      d.topRow := 0;
    END;
  END;
  d.nibblePhase := 0;
  d.binBitPos := 0;
  EnsureVisible(d);
END PageDown;

PROCEDURE Home(VAR d: Document);
BEGIN
  d.cursor := (d.cursor DIV BytesPerRow) * BytesPerRow;
  d.nibblePhase := 0;
  d.binBitPos := 0;
END Home;

PROCEDURE End(VAR d: Document);
VAR rowEnd, len: CARDINAL;
BEGIN
  len := StoreLen(d.store);
  rowEnd := (d.cursor DIV BytesPerRow) * BytesPerRow + BytesPerRow - 1;
  IF rowEnd >= len THEN
    IF len > 0 THEN rowEnd := len - 1; ELSE rowEnd := 0; END;
  END;
  d.cursor := rowEnd;
  d.nibblePhase := 0;
  d.binBitPos := 0;
END End;

(* ── Selection ──────────────────────────────────────── *)

PROCEDURE StartSelection(VAR d: Document);
BEGIN
  IF d.selAnchor = NoSelection THEN
    d.selAnchor := d.cursor;
  END;
END StartSelection;

PROCEDURE ClearSelection(VAR d: Document);
BEGIN
  d.selAnchor := NoSelection;
END ClearSelection;

PROCEDURE HasSelection(VAR d: Document): BOOLEAN;
BEGIN
  RETURN d.selAnchor # NoSelection;
END HasSelection;

PROCEDURE SelectionLow(VAR d: Document): CARDINAL;
BEGIN
  IF d.selAnchor = NoSelection THEN RETURN d.cursor; END;
  IF d.selAnchor < d.cursor THEN RETURN d.selAnchor;
  ELSE RETURN d.cursor;
  END;
END SelectionLow;

PROCEDURE SelectionHigh(VAR d: Document): CARDINAL;
BEGIN
  IF d.selAnchor = NoSelection THEN RETURN d.cursor; END;
  IF d.selAnchor > d.cursor THEN RETURN d.selAnchor;
  ELSE RETURN d.cursor;
  END;
END SelectionHigh;

(* ── Edit ───────────────────────────────────────────── *)

PROCEDURE InputHexNibble(VAR d: Document; nibble: CARDINAL);
VAR cur, hi, lo: CARDINAL;
BEGIN
  IF d.cursor >= StoreLen(d.store) THEN RETURN; END;
  cur := StoreGetByte(d.store, d.cursor);
  IF d.nibblePhase = 0 THEN
    lo := cur MOD 16;
    PutByte(d, d.cursor, (nibble * 16) + lo);
    d.nibblePhase := 1;
  ELSE
    hi := (cur DIV 16) * 16;
    PutByte(d, d.cursor, hi + (nibble MOD 16));
    d.nibblePhase := 0;
    IF d.cursor + 1 < StoreLen(d.store) THEN
      INC(d.cursor);
    END;
    EnsureVisible(d);
  END;
END InputHexNibble;

PROCEDURE InputAscii(VAR d: Document; ch: CHAR);
BEGIN
  IF d.cursor >= StoreLen(d.store) THEN RETURN; END;
  PutByte(d, d.cursor, ORD(ch));
  IF d.cursor + 1 < StoreLen(d.store) THEN
    INC(d.cursor);
  END;
  d.nibblePhase := 0;
  EnsureVisible(d);
END InputAscii;

PROCEDURE InputBinBit(VAR d: Document; bit: CARDINAL);
VAR cur, pw, i, newVal: CARDINAL;
BEGIN
  IF d.cursor >= StoreLen(d.store) THEN RETURN; END;
  cur := StoreGetByte(d.store, d.cursor);
  (* Compute power-of-2 mask for binBitPos: 0->128, 1->64, ..., 7->1 *)
  pw := 128;
  FOR i := 1 TO d.binBitPos DO pw := pw DIV 2; END;
  (* Clear the target bit *)
  newVal := cur - ((cur DIV pw) MOD 2) * pw;
  (* Set if bit=1 *)
  IF bit = 1 THEN
    newVal := newVal + pw;
  END;
  PutByte(d, d.cursor, newVal);
END InputBinBit;

PROCEDURE ToggleMode(VAR d: Document);
BEGIN
  IF d.editMode = ModeHex THEN
    d.editMode := ModeAscii;
  ELSE
    d.editMode := ModeHex;
  END;
  d.nibblePhase := 0;
  d.binBitPos := 0;
END ToggleMode;

(* ── Undo/Redo ─────────────────────────────────────── *)

PROCEDURE BeginGroup(VAR d: Document);
BEGIN
  CmdBeginGroup(d.history);
END BeginGroup;

PROCEDURE EndGroup(VAR d: Document);
BEGIN
  CmdEndGroup(d.history);
END EndGroup;

PROCEDURE Undo(VAR d: Document): BOOLEAN;
BEGIN
  RETURN CmdUndo(d.history, d.store);
END Undo;

PROCEDURE Redo(VAR d: Document): BOOLEAN;
BEGIN
  RETURN CmdRedo(d.history, d.store);
END Redo;

(* ── Scrolling ──────────────────────────────────────── *)

PROCEDURE EnsureVisible(VAR d: Document);
VAR cursorRow: CARDINAL;
BEGIN
  cursorRow := d.cursor DIV BytesPerRow;
  IF cursorRow < d.topRow THEN
    d.topRow := cursorRow;
  ELSIF cursorRow >= d.topRow + d.visibleRows THEN
    d.topRow := cursorRow - d.visibleRows + 1;
  END;
END EnsureVisible;

END Doc.

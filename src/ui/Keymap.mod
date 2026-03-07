IMPLEMENTATION MODULE Keymap;

FROM SYSTEM IMPORT ADR;
FROM Events IMPORT KeyCode, KeyMod, KeyRepeat, WheelY, MouseX, MouseY,
                   KEYDOWN, MOUSEWHEEL, MOUSEDOWN, MOUSEMOVE, MOUSEUP,
                   WINDOW_EVENT,
                   WindowEvent, WEVT_RESIZED, WEVT_EXPOSED,
                   MOD_SHIFT, MOD_CTRL, MOD_GUI,
                   KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
                   KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END,
                   KEY_TAB, KEY_ESCAPE, KEY_RETURN, KEY_BACKSPACE,
                   QUIT_EVENT, TEXTINPUT,
                   TextInput;
FROM Doc IMPORT Document, MoveCursorLeft, MoveCursorRight,
                MoveCursorUp, MoveCursorDown, PageUp, PageDown,
                Home, End, ToggleMode, StartSelection, ClearSelection,
                InputHexNibble, InputAscii, InputBinBit,
                ModeHex, ModeAscii, ModeBin, EnsureVisible,
                Save, Undo, Redo, FileLen, TotalRows, NoSelection,
                HasSelection, SelectionLow, SelectionHigh,
                GetByte, PutByte, ReadBlock, BytesPerRow,
                BeginGroup, EndGroup;
FROM View IMPORT ViewState, HitTest, DragHitTest, BinHitTest, Resize;
FROM Gfx IMPORT GetWindowWidth, GetWindowHeight, SetClipboard, GetClipboard;
FROM Search IMPORT FindNext;
FROM SearchState IMPORT SetSearchMode, SetSearchBuf, SetSearchIsHex, SetNotFound;
FROM GotoState IMPORT SetGotoMode, SetGotoBuf, SetGotoError;
FROM FillState IMPORT SetFillMode, SetFillBuf;
FROM ReplaceState IMPORT SetReplaceMode, SetReplacePhase,
                         SetSearchBuf AS SetReplSearchBuf,
                         SetReplaceBuf AS SetReplReplaceBuf,
                         SetIsHex AS SetReplIsHex,
                         SetNotFound AS SetReplNotFound,
                         PhaseSearch, PhaseReplace, PhaseConfirm;
FROM ExportState IMPORT SetExportMode, SetExportBuf, SetExportError;
FROM HistogramState IMPORT SetShowHistogram, IsShowHistogram,
                           SetFrequency, SetMaxFrequency, SetTotalBytes,
                           ClearFrequencies;
FROM EndianState IMPORT ToggleEndianness;
FROM Sys IMPORT m2sys_fopen, m2sys_fwrite_bytes, m2sys_fclose;
(*$IF MACOS *)
FROM MacBridge IMPORT mac_show_about;
(*$END *)

CONST
  HexDigit = "0123456789ABCDEF";

PROCEDURE PowerOf2(n: INTEGER): CARDINAL;
VAR r: CARDINAL; i: INTEGER;
BEGIN
  r := 1;
  FOR i := 1 TO n DO r := r * 2; END;
  RETURN r;
END PowerOf2;

VAR
  dragging: BOOLEAN;
  dragAnchor: CARDINAL;

  (* Scrollbar drag state *)
  sbDragging: BOOLEAN;
  sbDragStartY: INTEGER;
  sbDragStartRow: CARDINAL;

  (* Search state — local copies; synced to SearchState for View *)
  searchMode: BOOLEAN;
  searchBuf: ARRAY [0..127] OF CHAR;
  searchLen: INTEGER;
  searchIsHex: BOOLEAN;
  savedCursor: CARDINAL;
  savedAnchor: CARDINAL;
  lastBuf: ARRAY [0..127] OF CHAR;
  lastLen: INTEGER;
  lastIsHex: BOOLEAN;
  notFound: BOOLEAN;

  (* Goto state — local copies; synced to GotoState for View *)
  gotoMode: BOOLEAN;
  gotoBuf: ARRAY [0..31] OF CHAR;
  gotoLen: INTEGER;
  gotoError: BOOLEAN;

  (* Fill state — local copies; synced to FillState for View *)
  fillMode: BOOLEAN;
  fillBuf: ARRAY [0..3] OF CHAR;
  fillLen: INTEGER;

  (* Replace state — local copies; synced to ReplaceState for View *)
  replaceMode: BOOLEAN;
  replacePhase: INTEGER;  (* 0=search, 1=replace, 2=confirm *)
  replSearchBuf: ARRAY [0..127] OF CHAR;
  replSearchLen: INTEGER;
  replReplaceBuf: ARRAY [0..127] OF CHAR;
  replReplaceLen: INTEGER;
  replIsHex: BOOLEAN;
  replNotFound: BOOLEAN;
  replSavedCursor: CARDINAL;
  replSavedAnchor: CARDINAL;

  (* Export state — local copies; synced to ExportState for View *)
  exportMode: BOOLEAN;
  exportBuf: ARRAY [0..255] OF CHAR;
  exportLen: INTEGER;
  exportError: BOOLEAN;

(* ── Sync search state to SearchState module ───────── *)

PROCEDURE SyncState;
BEGIN
  SetSearchMode(searchMode);
  SetSearchBuf(searchBuf, searchLen);
  SetSearchIsHex(searchIsHex);
  SetNotFound(notFound);
END SyncState;

PROCEDURE SyncGotoState;
BEGIN
  SetGotoMode(gotoMode);
  SetGotoBuf(gotoBuf, gotoLen);
  SetGotoError(gotoError);
END SyncGotoState;

PROCEDURE SyncFillState;
BEGIN
  SetFillMode(fillMode);
  SetFillBuf(fillBuf, fillLen);
END SyncFillState;

PROCEDURE SyncReplaceState;
BEGIN
  SetReplaceMode(replaceMode);
  IF replacePhase = 0 THEN
    SetReplacePhase(PhaseSearch);
  ELSIF replacePhase = 1 THEN
    SetReplacePhase(PhaseReplace);
  ELSE
    SetReplacePhase(PhaseConfirm);
  END;
  SetReplSearchBuf(replSearchBuf, replSearchLen);
  SetReplReplaceBuf(replReplaceBuf, replReplaceLen);
  SetReplIsHex(replIsHex);
  SetReplNotFound(replNotFound);
END SyncReplaceState;

PROCEDURE SyncExportState;
BEGIN
  SetExportMode(exportMode);
  SetExportBuf(exportBuf, exportLen);
  SetExportError(exportError);
END SyncExportState;

(* ── Search helpers ────────────────────────────────── *)

PROCEDURE EnterSearch(VAR d: Document);
BEGIN
  searchMode := TRUE;
  searchLen := 0;
  searchBuf[0] := 0C;
  searchIsHex := (d.editMode = ModeHex);
  notFound := FALSE;
  savedCursor := d.cursor;
  savedAnchor := d.selAnchor;
  SyncState;
END EnterSearch;

PROCEDURE ExitSearch();
BEGIN
  searchMode := FALSE;
  SyncState;
END ExitSearch;

PROCEDURE IsHexChar(ch: CHAR): BOOLEAN;
BEGIN
  RETURN ((ch >= "0") AND (ch <= "9")) OR
         ((ch >= "a") AND (ch <= "f")) OR
         ((ch >= "A") AND (ch <= "F"));
END IsHexChar;

PROCEDURE IsPrintable(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ORD(ch) >= 32) AND (ORD(ch) <= 126);
END IsPrintable;

PROCEDURE DoSearch(VAR d: Document; fromOff: CARDINAL);
VAR foundOff, foundLen: CARDINAL;
    i: INTEGER;
BEGIN
  notFound := FALSE;
  IF searchLen = 0 THEN RETURN; END;

  (* Save current search as last search *)
  FOR i := 0 TO searchLen - 1 DO
    lastBuf[i] := searchBuf[i];
  END;
  lastLen := searchLen;
  lastIsHex := searchIsHex;

  IF FindNext(d, searchBuf, searchLen, searchIsHex, fromOff,
              foundOff, foundLen) THEN
    d.cursor := foundOff;
    d.selAnchor := foundOff + foundLen - 1;
    d.nibblePhase := 0;
    EnsureVisible(d);
  ELSE
    notFound := TRUE;
  END;
END DoSearch;

PROCEDURE DoFindNext(VAR d: Document);
VAR foundOff, foundLen: CARDINAL;
BEGIN
  IF lastLen = 0 THEN RETURN; END;
  notFound := FALSE;
  IF FindNext(d, lastBuf, lastLen, lastIsHex, d.cursor,
              foundOff, foundLen) THEN
    d.cursor := foundOff;
    d.selAnchor := foundOff + foundLen - 1;
    d.nibblePhase := 0;
    EnsureVisible(d);
  ELSE
    notFound := TRUE;
  END;
  SyncState;
END DoFindNext;

(* ── Search event handler ──────────────────────────── *)

PROCEDURE HandleSearchEvent(evType, key, mods: INTEGER;
                            VAR d: Document): Action;
VAR
  textBuf: ARRAY [0..7] OF CHAR;
  ch: CHAR;
BEGIN
  IF evType = KEYDOWN THEN
    IF key = KEY_ESCAPE THEN
      (* Cancel: restore cursor/selection *)
      d.cursor := savedCursor;
      d.selAnchor := savedAnchor;
      d.nibblePhase := 0;
      EnsureVisible(d);
      ExitSearch();
      RETURN ActRedraw;
    END;

    IF (key = KEY_RETURN) OR (key = 13) THEN
      (* Execute search *)
      DoSearch(d, savedCursor);
      ExitSearch();
      RETURN ActRedraw;
    END;

    IF key = KEY_TAB THEN
      (* Toggle hex/ASCII mode *)
      searchIsHex := NOT searchIsHex;
      searchLen := 0;
      searchBuf[0] := 0C;
      notFound := FALSE;
      SyncState;
      RETURN ActRedraw;
    END;

    IF key = KEY_BACKSPACE THEN
      IF searchLen > 0 THEN
        DEC(searchLen);
        searchBuf[searchLen] := 0C;
        notFound := FALSE;
        SyncState;
      END;
      RETURN ActRedraw;
    END;

    RETURN ActRedraw;
  END;

  IF evType = TEXTINPUT THEN
    TextInput(textBuf);
    ch := textBuf[0];
    IF searchLen < 127 THEN
      IF searchIsHex THEN
        IF IsHexChar(ch) THEN
          searchBuf[searchLen] := ch;
          INC(searchLen);
          searchBuf[searchLen] := 0C;
          notFound := FALSE;
          SyncState;
        END;
      ELSE
        IF IsPrintable(ch) THEN
          searchBuf[searchLen] := ch;
          INC(searchLen);
          searchBuf[searchLen] := 0C;
          notFound := FALSE;
          SyncState;
        END;
      END;
    END;
    RETURN ActRedraw;
  END;

  (* Consume all other events silently in search mode *)
  RETURN ActNone;
END HandleSearchEvent;

(* ── Goto helpers ──────────────────────────────────── *)

PROCEDURE EnterGoto(VAR d: Document);
BEGIN
  gotoMode := TRUE;
  gotoLen := 0;
  gotoBuf[0] := 0C;
  gotoError := FALSE;
  SyncGotoState;
END EnterGoto;

PROCEDURE ExitGoto;
BEGIN
  gotoMode := FALSE;
  SyncGotoState;
END ExitGoto;

PROCEDURE HexCharVal(ch: CHAR): CARDINAL;
BEGIN
  IF (ch >= "0") AND (ch <= "9") THEN
    RETURN ORD(ch) - ORD("0");
  ELSIF (ch >= "a") AND (ch <= "f") THEN
    RETURN ORD(ch) - ORD("a") + 10;
  ELSIF (ch >= "A") AND (ch <= "F") THEN
    RETURN ORD(ch) - ORD("A") + 10;
  END;
  RETURN 0;
END HexCharVal;

PROCEDURE ParseHexOffset(): CARDINAL;
VAR i: INTEGER;
    val: CARDINAL;
BEGIN
  val := 0;
  FOR i := 0 TO gotoLen - 1 DO
    val := val * 16 + HexCharVal(gotoBuf[i]);
  END;
  RETURN val;
END ParseHexOffset;

PROCEDURE HandleGotoEvent(evType, key, mods: INTEGER;
                          VAR d: Document): Action;
VAR
  textBuf: ARRAY [0..7] OF CHAR;
  ch: CHAR;
  offset: CARDINAL;
BEGIN
  IF evType = KEYDOWN THEN
    IF key = KEY_ESCAPE THEN
      ExitGoto;
      RETURN ActRedraw;
    END;

    IF (key = KEY_RETURN) OR (key = 13) THEN
      IF gotoLen > 0 THEN
        offset := ParseHexOffset();
        IF offset < FileLen(d) THEN
          ClearSelection(d);
          d.cursor := offset;
          d.nibblePhase := 0;
          EnsureVisible(d);
        ELSE
          gotoError := TRUE;
          SyncGotoState;
          RETURN ActRedraw;
        END;
      END;
      ExitGoto;
      RETURN ActRedraw;
    END;

    IF key = KEY_BACKSPACE THEN
      IF gotoLen > 0 THEN
        DEC(gotoLen);
        gotoBuf[gotoLen] := 0C;
        gotoError := FALSE;
        SyncGotoState;
      END;
      RETURN ActRedraw;
    END;

    RETURN ActRedraw;
  END;

  IF evType = TEXTINPUT THEN
    TextInput(textBuf);
    ch := textBuf[0];
    IF (gotoLen < 31) AND IsHexChar(ch) THEN
      gotoBuf[gotoLen] := ch;
      INC(gotoLen);
      gotoBuf[gotoLen] := 0C;
      gotoError := FALSE;
      SyncGotoState;
    END;
    RETURN ActRedraw;
  END;

  RETURN ActNone;
END HandleGotoEvent;

(* ── Copy/Paste helpers ────────────────────────────── *)

PROCEDURE DoCopy(VAR d: Document);
VAR
  lo, hi, off: CARDINAL;
  byteVal: CARDINAL;
  clipBuf: ARRAY [0..4095] OF CHAR;
  pos: INTEGER;
BEGIN
  IF NOT HasSelection(d) THEN RETURN; END;
  lo := SelectionLow(d);
  hi := SelectionHigh(d);
  pos := 0;
  off := lo;
  WHILE (off <= hi) AND (pos < 4090) DO
    byteVal := GetByte(d, off);
    IF pos > 0 THEN
      clipBuf[pos] := " ";
      INC(pos);
    END;
    clipBuf[pos] := HexDigit[byteVal DIV 16];
    INC(pos);
    clipBuf[pos] := HexDigit[byteVal MOD 16];
    INC(pos);
    INC(off);
  END;
  clipBuf[pos] := 0C;
  SetClipboard(clipBuf);
END DoCopy;

PROCEDURE DoPaste(VAR d: Document);
VAR
  clipBuf: ARRAY [0..4095] OF CHAR;
  i, len: INTEGER;
  ch: CHAR;
  hi, lo: CARDINAL;
  byteVal: CARDINAL;
  gotHi: BOOLEAN;
  isHex: BOOLEAN;
  cursor: CARDINAL;
  fileSize: CARDINAL;
BEGIN
  GetClipboard(clipBuf);

  (* Find length *)
  len := 0;
  WHILE (len <= 4095) AND (clipBuf[len] # 0C) DO INC(len); END;
  IF len = 0 THEN RETURN; END;

  (* Check if it looks like hex: only hex chars and spaces *)
  isHex := TRUE;
  i := 0;
  WHILE i < len DO
    ch := clipBuf[i];
    IF (ch # " ") AND NOT IsHexChar(ch) THEN
      isHex := FALSE;
      i := len; (* break *)
    END;
    INC(i);
  END;

  cursor := d.cursor;
  fileSize := FileLen(d);

  BeginGroup(d);
  IF isHex THEN
    (* Parse hex pairs, skip spaces *)
    i := 0;
    gotHi := FALSE;
    hi := 0;
    WHILE i < len DO
      ch := clipBuf[i];
      IF ch = " " THEN
        (* skip *)
      ELSIF IsHexChar(ch) THEN
        IF NOT gotHi THEN
          hi := HexCharVal(ch);
          gotHi := TRUE;
        ELSE
          byteVal := hi * 16 + HexCharVal(ch);
          IF cursor < fileSize THEN
            PutByte(d, cursor, byteVal);
            INC(cursor);
          END;
          gotHi := FALSE;
        END;
      END;
      INC(i);
    END;
    (* Handle trailing single nibble *)
    IF gotHi AND (cursor < fileSize) THEN
      PutByte(d, cursor, hi);
      INC(cursor);
    END;
  ELSE
    (* Raw ASCII paste *)
    i := 0;
    WHILE i < len DO
      IF cursor < fileSize THEN
        PutByte(d, cursor, ORD(clipBuf[i]));
        INC(cursor);
      END;
      INC(i);
    END;
  END;
  EndGroup(d);

  (* Advance cursor past pasted bytes *)
  IF cursor > 0 THEN
    d.cursor := cursor - 1;
  END;
  d.nibblePhase := 0;
  ClearSelection(d);
  EnsureVisible(d);
END DoPaste;

(* ── Fill helpers ──────────────────────────────────── *)

PROCEDURE EnterFill(VAR d: Document);
BEGIN
  IF NOT HasSelection(d) THEN RETURN; END;
  fillMode := TRUE;
  fillLen := 0;
  fillBuf[0] := 0C;
  SyncFillState;
END EnterFill;

PROCEDURE ExitFill;
BEGIN
  fillMode := FALSE;
  SyncFillState;
END ExitFill;

PROCEDURE HandleFillEvent(evType, key, mods: INTEGER;
                          VAR d: Document): Action;
VAR
  textBuf: ARRAY [0..7] OF CHAR;
  ch: CHAR;
  byteVal, lo, hi, off: CARDINAL;
BEGIN
  IF evType = KEYDOWN THEN
    IF key = KEY_ESCAPE THEN
      ExitFill;
      RETURN ActRedraw;
    END;

    IF (key = KEY_RETURN) OR (key = 13) THEN
      IF (fillLen > 0) AND HasSelection(d) THEN
        byteVal := 0;
        IF fillLen = 1 THEN
          byteVal := HexCharVal(fillBuf[0]);
        ELSE
          byteVal := HexCharVal(fillBuf[0]) * 16 + HexCharVal(fillBuf[1]);
        END;
        lo := SelectionLow(d);
        hi := SelectionHigh(d);
        BeginGroup(d);
        off := lo;
        WHILE off <= hi DO
          PutByte(d, off, byteVal);
          INC(off);
        END;
        EndGroup(d);
      END;
      ExitFill;
      RETURN ActRedraw;
    END;

    IF key = KEY_BACKSPACE THEN
      IF fillLen > 0 THEN
        DEC(fillLen);
        fillBuf[fillLen] := 0C;
        SyncFillState;
      END;
      RETURN ActRedraw;
    END;

    RETURN ActRedraw;
  END;

  IF evType = TEXTINPUT THEN
    TextInput(textBuf);
    ch := textBuf[0];
    IF (fillLen < 2) AND IsHexChar(ch) THEN
      fillBuf[fillLen] := ch;
      INC(fillLen);
      fillBuf[fillLen] := 0C;
      SyncFillState;
    END;
    RETURN ActRedraw;
  END;

  RETURN ActNone;
END HandleFillEvent;

(* ── Replace helpers ────────────────────────────────── *)

PROCEDURE EnterReplace(VAR d: Document);
BEGIN
  replaceMode := TRUE;
  replacePhase := 0;  (* PhaseSearch *)
  replSearchLen := 0;
  replSearchBuf[0] := 0C;
  replReplaceLen := 0;
  replReplaceBuf[0] := 0C;
  replIsHex := (d.editMode = ModeHex);
  replNotFound := FALSE;
  replSavedCursor := d.cursor;
  replSavedAnchor := d.selAnchor;
  SyncReplaceState;
END EnterReplace;

PROCEDURE ExitReplace;
BEGIN
  replaceMode := FALSE;
  SyncReplaceState;
END ExitReplace;

(* Parse hex string into byte values, return count *)
PROCEDURE ParseReplHex(VAR buf: ARRAY OF CHAR; bufLen: INTEGER;
                       VAR bytes: ARRAY OF CARDINAL): INTEGER;
VAR i, n: INTEGER;
BEGIN
  n := 0;
  i := 0;
  WHILE (i + 1 < bufLen) AND (n <= INTEGER(HIGH(bytes))) DO
    IF IsHexChar(buf[i]) AND IsHexChar(buf[i+1]) THEN
      bytes[n] := HexCharVal(buf[i]) * 16 + HexCharVal(buf[i+1]);
      INC(n);
    END;
    INC(i, 2);
  END;
  RETURN n;
END ParseReplHex;

PROCEDURE DoReplace(VAR d: Document; atOff, matchLen: CARDINAL);
VAR
  replBytes: ARRAY [0..63] OF CARDINAL;
  nRepl: INTEGER;
  i: INTEGER;
  writeLen: INTEGER;
BEGIN
  IF replIsHex THEN
    nRepl := ParseReplHex(replReplaceBuf, replReplaceLen, replBytes);
  ELSE
    nRepl := replReplaceLen;
    IF nRepl > 64 THEN nRepl := 64; END;
    FOR i := 0 TO nRepl - 1 DO
      replBytes[i] := ORD(replReplaceBuf[i]);
    END;
  END;
  (* Write min(replLen, matchLen) bytes — overwrite only, no resize *)
  writeLen := nRepl;
  IF CARDINAL(writeLen) > matchLen THEN writeLen := INTEGER(matchLen); END;
  FOR i := 0 TO writeLen - 1 DO
    PutByte(d, atOff + CARDINAL(i), replBytes[i]);
  END;
END DoReplace;

(* Search using replace search buffer, from given offset *)
PROCEDURE ReplFindNext(VAR d: Document; fromOff: CARDINAL): BOOLEAN;
VAR foundOff, foundLen: CARDINAL;
BEGIN
  IF replSearchLen = 0 THEN RETURN FALSE; END;
  IF FindNext(d, replSearchBuf, replSearchLen, replIsHex, fromOff,
              foundOff, foundLen) THEN
    d.cursor := foundOff;
    d.selAnchor := foundOff + foundLen - 1;
    d.nibblePhase := 0;
    EnsureVisible(d);
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END;
END ReplFindNext;

PROCEDURE HandleReplaceEvent(evType, key, mods: INTEGER;
                             VAR d: Document): Action;
VAR
  textBuf: ARRAY [0..7] OF CHAR;
  ch: CHAR;
  matchOff, matchLen: CARDINAL;
  foundOff, foundLen: CARDINAL;
BEGIN
  IF evType = KEYDOWN THEN
    IF key = KEY_ESCAPE THEN
      IF replacePhase = 0 THEN
        (* Cancel: restore cursor/selection *)
        d.cursor := replSavedCursor;
        d.selAnchor := replSavedAnchor;
        d.nibblePhase := 0;
        EnsureVisible(d);
      END;
      ExitReplace;
      RETURN ActRedraw;
    END;

    (* Phase 0: Search input *)
    IF replacePhase = 0 THEN
      IF (key = KEY_RETURN) OR (key = 13) THEN
        IF replSearchLen > 0 THEN
          replNotFound := FALSE;
          IF ReplFindNext(d, replSavedCursor) THEN
            replacePhase := 1;  (* go to replace input *)
          ELSE
            replNotFound := TRUE;
          END;
          SyncReplaceState;
        END;
        RETURN ActRedraw;
      END;

      IF key = KEY_TAB THEN
        replIsHex := NOT replIsHex;
        replSearchLen := 0;
        replSearchBuf[0] := 0C;
        replNotFound := FALSE;
        SyncReplaceState;
        RETURN ActRedraw;
      END;

      IF key = KEY_BACKSPACE THEN
        IF replSearchLen > 0 THEN
          DEC(replSearchLen);
          replSearchBuf[replSearchLen] := 0C;
          replNotFound := FALSE;
          SyncReplaceState;
        END;
        RETURN ActRedraw;
      END;
      RETURN ActRedraw;
    END;

    (* Phase 1: Replace input *)
    IF replacePhase = 1 THEN
      IF (key = KEY_RETURN) OR (key = 13) THEN
        replacePhase := 2;  (* go to confirm *)
        SyncReplaceState;
        RETURN ActRedraw;
      END;

      IF key = KEY_BACKSPACE THEN
        IF replReplaceLen > 0 THEN
          DEC(replReplaceLen);
          replReplaceBuf[replReplaceLen] := 0C;
          SyncReplaceState;
        END;
        RETURN ActRedraw;
      END;
      RETURN ActRedraw;
    END;

    (* Phase 2: Confirm *)
    IF replacePhase = 2 THEN
      IF (key = ORD("y")) OR (key = ORD("Y")) THEN
        (* Replace current match, find next *)
        IF HasSelection(d) THEN
          matchOff := SelectionLow(d);
          matchLen := SelectionHigh(d) - matchOff + 1;
          BeginGroup(d);
          DoReplace(d, matchOff, matchLen);
          EndGroup(d);
          IF ReplFindNext(d, matchOff) THEN
            (* stay in confirm *)
          ELSE
            ExitReplace;
          END;
        ELSE
          ExitReplace;
        END;
        RETURN ActRedraw;
      END;

      IF (key = ORD("n")) OR (key = ORD("N")) THEN
        (* Skip, find next *)
        IF HasSelection(d) THEN
          IF ReplFindNext(d, d.cursor) THEN
            (* stay in confirm *)
          ELSE
            ExitReplace;
          END;
        ELSE
          ExitReplace;
        END;
        RETURN ActRedraw;
      END;

      IF (key = ORD("a")) OR (key = ORD("A")) THEN
        (* Replace all *)
        BeginGroup(d);
        WHILE HasSelection(d) DO
          matchOff := SelectionLow(d);
          matchLen := SelectionHigh(d) - matchOff + 1;
          DoReplace(d, matchOff, matchLen);
          IF NOT ReplFindNext(d, matchOff) THEN
            ClearSelection(d);
          END;
        END;
        EndGroup(d);
        ExitReplace;
        RETURN ActRedraw;
      END;

      RETURN ActRedraw;
    END;

    RETURN ActRedraw;
  END;

  IF evType = TEXTINPUT THEN
    TextInput(textBuf);
    ch := textBuf[0];

    (* Phase 0: Search text input *)
    IF replacePhase = 0 THEN
      IF replSearchLen < 127 THEN
        IF replIsHex THEN
          IF IsHexChar(ch) THEN
            replSearchBuf[replSearchLen] := ch;
            INC(replSearchLen);
            replSearchBuf[replSearchLen] := 0C;
            replNotFound := FALSE;
            SyncReplaceState;
          END;
        ELSE
          IF IsPrintable(ch) THEN
            replSearchBuf[replSearchLen] := ch;
            INC(replSearchLen);
            replSearchBuf[replSearchLen] := 0C;
            replNotFound := FALSE;
            SyncReplaceState;
          END;
        END;
      END;
      RETURN ActRedraw;
    END;

    (* Phase 1: Replace text input *)
    IF replacePhase = 1 THEN
      IF replReplaceLen < 127 THEN
        IF replIsHex THEN
          IF IsHexChar(ch) THEN
            replReplaceBuf[replReplaceLen] := ch;
            INC(replReplaceLen);
            replReplaceBuf[replReplaceLen] := 0C;
            SyncReplaceState;
          END;
        ELSE
          IF IsPrintable(ch) THEN
            replReplaceBuf[replReplaceLen] := ch;
            INC(replReplaceLen);
            replReplaceBuf[replReplaceLen] := 0C;
            SyncReplaceState;
          END;
        END;
      END;
      RETURN ActRedraw;
    END;

    RETURN ActRedraw;
  END;

  (* Consume all other events silently in replace mode *)
  RETURN ActNone;
END HandleReplaceEvent;

(* ── Export helpers ──────────────────────────────────── *)

PROCEDURE EnterExport(VAR d: Document);
BEGIN
  IF NOT HasSelection(d) THEN RETURN; END;
  exportMode := TRUE;
  exportLen := 0;
  exportBuf[0] := 0C;
  exportError := FALSE;
  SyncExportState;
END EnterExport;

PROCEDURE ExitExport;
BEGIN
  exportMode := FALSE;
  SyncExportState;
END ExitExport;

PROCEDURE DoExport(VAR d: Document);
VAR
  lo, hi, off: CARDINAL;
  hnd, written: INTEGER;
  chunk: ARRAY [0..4095] OF CHAR;
  chunkLen: INTEGER;
  writeMode: ARRAY [0..3] OF CHAR;
BEGIN
  exportError := FALSE;
  IF NOT HasSelection(d) THEN
    exportError := TRUE;
    SyncExportState;
    RETURN;
  END;

  writeMode[0] := "w"; writeMode[1] := "b"; writeMode[2] := 0C;
  hnd := m2sys_fopen(ADR(exportBuf), ADR(writeMode));
  IF hnd < 0 THEN
    exportError := TRUE;
    SyncExportState;
    RETURN;
  END;

  lo := SelectionLow(d);
  hi := SelectionHigh(d);
  off := lo;
  WHILE off <= hi DO
    chunkLen := 0;
    WHILE (off <= hi) AND (chunkLen < 4096) DO
      chunk[chunkLen] := CHR(GetByte(d, off));
      INC(chunkLen);
      INC(off);
    END;
    written := m2sys_fwrite_bytes(hnd, ADR(chunk), chunkLen);
    IF written < chunkLen THEN
      exportError := TRUE;
    END;
  END;

  IF m2sys_fclose(hnd) < 0 THEN
    exportError := TRUE;
  END;
  SyncExportState;
END DoExport;

PROCEDURE HandleExportEvent(evType, key, mods: INTEGER;
                            VAR d: Document): Action;
VAR
  textBuf: ARRAY [0..7] OF CHAR;
  ch: CHAR;
BEGIN
  IF evType = KEYDOWN THEN
    IF key = KEY_ESCAPE THEN
      ExitExport;
      RETURN ActRedraw;
    END;

    IF (key = KEY_RETURN) OR (key = 13) THEN
      IF exportLen > 0 THEN
        DoExport(d);
        IF NOT exportError THEN
          ExitExport;
        END;
      END;
      RETURN ActRedraw;
    END;

    IF key = KEY_BACKSPACE THEN
      IF exportLen > 0 THEN
        DEC(exportLen);
        exportBuf[exportLen] := 0C;
        exportError := FALSE;
        SyncExportState;
      END;
      RETURN ActRedraw;
    END;

    RETURN ActRedraw;
  END;

  IF evType = TEXTINPUT THEN
    TextInput(textBuf);
    ch := textBuf[0];
    IF (exportLen < 255) AND IsPrintable(ch) THEN
      exportBuf[exportLen] := ch;
      INC(exportLen);
      exportBuf[exportLen] := 0C;
      exportError := FALSE;
      SyncExportState;
    END;
    RETURN ActRedraw;
  END;

  RETURN ActNone;
END HandleExportEvent;

(* ── Histogram helpers ──────────────────────────────── *)

PROCEDURE ComputeHistogram(VAR d: Document);
VAR
  localFreq: ARRAY [0..255] OF CARDINAL;
  block: ARRAY [0..4095] OF CHAR;
  i, n: CARDINAL;
  fileSize, off, maxF: CARDINAL;
BEGIN
  FOR i := 0 TO 255 DO
    localFreq[i] := 0;
  END;
  fileSize := FileLen(d);
  off := 0;
  WHILE off < fileSize DO
    n := ReadBlock(d, off, block, 4096);
    IF n = 0 THEN EXIT; END;
    FOR i := 0 TO n - 1 DO
      INC(localFreq[ORD(block[i])]);
    END;
    INC(off, n);
  END;
  maxF := 0;
  ClearFrequencies;
  FOR i := 0 TO 255 DO
    SetFrequency(i, localFreq[i]);
    IF localFreq[i] > maxF THEN
      maxF := localFreq[i];
    END;
  END;
  SetMaxFrequency(maxF);
  SetTotalBytes(fileSize);
END ComputeHistogram;

PROCEDURE ToggleHistogram(VAR d: Document);
BEGIN
  IF IsShowHistogram() THEN
    SetShowHistogram(FALSE);
  ELSE
    ComputeHistogram(d);
    SetShowHistogram(TRUE);
  END;
END ToggleHistogram;

(* ── Main event handler ────────────────────────────── *)

PROCEDURE HandleEvent(evType: INTEGER; VAR d: Document; VAR v: ViewState): Action;
VAR
  key, mods, wy: INTEGER;
  shifted, ctrl: BOOLEAN;
  nibble: INTEGER;
  hitOff: CARDINAL;
  binHitBit: CARDINAL;
  curBit: CARDINAL;
  textBuf: ARRAY [0..7] OF CHAR;
  ch: CHAR;
  totalR: CARDINAL;
  trackH, thumbH, thumbY, deltaY: INTEGER;
  newRow: INTEGER;
BEGIN
  IF evType = QUIT_EVENT THEN RETURN ActQuit; END;

  IF evType = WINDOW_EVENT THEN
    IF (WindowEvent() = WEVT_RESIZED) OR (WindowEvent() = WEVT_EXPOSED) THEN
      RETURN ActRedraw;
    END;
    RETURN ActNone;
  END;

  (* Read key/mods for KEYDOWN early so modal handlers can use them *)
  IF evType = KEYDOWN THEN
    key := KeyCode();
    mods := KeyMod();
  ELSE
    key := 0;
    mods := 0;
  END;

  (* Modal intercepts — fill > goto > search > replace > export *)
  IF fillMode THEN
    RETURN HandleFillEvent(evType, key, mods, d);
  END;

  IF gotoMode THEN
    RETURN HandleGotoEvent(evType, key, mods, d);
  END;

  IF searchMode THEN
    RETURN HandleSearchEvent(evType, key, mods, d);
  END;

  IF replaceMode THEN
    RETURN HandleReplaceEvent(evType, key, mods, d);
  END;

  IF exportMode THEN
    RETURN HandleExportEvent(evType, key, mods, d);
  END;

  IF evType = MOUSEWHEEL THEN
    wy := WheelY();
    IF wy > 0 THEN
      IF d.topRow >= 3 THEN
        DEC(d.topRow, 3);
      ELSE
        d.topRow := 0;
      END;
    ELSIF wy < 0 THEN
      INC(d.topRow, 3);
      (* Clamp: don't scroll past last row *)
      IF TotalRows(d) > d.visibleRows THEN
        IF d.topRow > TotalRows(d) - d.visibleRows THEN
          d.topRow := TotalRows(d) - d.visibleRows;
        END;
      ELSE
        d.topRow := 0;
      END;
    END;
    RETURN ActRedraw;
  END;

  IF evType = MOUSEDOWN THEN
    (* Scrollbar click *)
    totalR := TotalRows(d);
    IF (MouseX() >= v.layout.sbX) AND (totalR > d.visibleRows) THEN
      trackH := v.layout.statusY - v.layout.padY;
      thumbH := INTEGER(d.visibleRows * CARDINAL(trackH) DIV totalR);
      IF thumbH < 20 THEN thumbH := 20; END;
      IF totalR > CARDINAL(trackH) THEN
        thumbY := v.layout.padY + INTEGER(d.topRow DIV (totalR DIV CARDINAL(trackH)));
      ELSE
        thumbY := v.layout.padY + INTEGER(d.topRow * CARDINAL(trackH) DIV totalR);
      END;
      IF thumbY + thumbH > v.layout.statusY THEN
        thumbY := v.layout.statusY - thumbH;
      END;
      IF (MouseY() >= thumbY) AND (MouseY() < thumbY + thumbH) THEN
        (* Drag the thumb *)
        sbDragging := TRUE;
        sbDragStartY := MouseY();
        sbDragStartRow := d.topRow;
      ELSIF MouseY() < thumbY THEN
        (* Page up *)
        IF d.topRow >= d.visibleRows THEN
          DEC(d.topRow, d.visibleRows);
        ELSE
          d.topRow := 0;
        END;
      ELSE
        (* Page down *)
        INC(d.topRow, d.visibleRows);
        IF totalR > d.visibleRows THEN
          IF d.topRow > totalR - d.visibleRows THEN
            d.topRow := totalR - d.visibleRows;
          END;
        ELSE
          d.topRow := 0;
        END;
      END;
      RETURN ActRedraw;
    END;
    IF BinHitTest(v, d, MouseX(), MouseY(), binHitBit) THEN
      d.editMode := ModeBin;
      d.binBitPos := binHitBit;
      (* Toggle the clicked bit *)
      IF d.cursor < FileLen(d) THEN
        curBit := GetByte(d, d.cursor);
        (* Check current bit value at binHitBit position *)
        IF ((curBit DIV PowerOf2(7 - INTEGER(binHitBit))) MOD 2) = 1 THEN
          InputBinBit(d, 0);
        ELSE
          InputBinBit(d, 1);
        END;
      END;
      RETURN ActRedraw;
    END;
    IF HitTest(v, d, MouseX(), MouseY(), hitOff) THEN
      mods := KeyMod();
      shifted := (mods MOD (MOD_SHIFT * 2)) DIV MOD_SHIFT = 1;
      IF shifted THEN
        StartSelection(d);
        d.cursor := hitOff;
        d.nibblePhase := 0;
      ELSE
        ClearSelection(d);
        d.cursor := hitOff;
        d.nibblePhase := 0;
        dragging := TRUE;
        dragAnchor := hitOff;
      END;
      RETURN ActRedraw;
    END;
    RETURN ActNone;
  END;

  IF evType = MOUSEMOVE THEN
    IF sbDragging THEN
      totalR := TotalRows(d);
      trackH := v.layout.statusY - v.layout.padY;
      IF (totalR > d.visibleRows) AND (trackH > 0) THEN
        deltaY := MouseY() - sbDragStartY;
        IF totalR > CARDINAL(trackH) THEN
          newRow := INTEGER(sbDragStartRow) + deltaY * INTEGER(totalR DIV CARDINAL(trackH));
        ELSE
          newRow := INTEGER(sbDragStartRow) + deltaY * INTEGER(totalR) DIV trackH;
        END;
        IF newRow < 0 THEN newRow := 0; END;
        IF CARDINAL(newRow) + d.visibleRows > totalR THEN
          newRow := INTEGER(totalR - d.visibleRows);
        END;
        d.topRow := CARDINAL(newRow);
      END;
      RETURN ActRedraw;
    END;
    IF dragging THEN
      IF DragHitTest(v, d, MouseX(), MouseY(), hitOff) THEN
        IF hitOff # dragAnchor THEN
          d.selAnchor := dragAnchor;
          d.cursor := hitOff;
          d.nibblePhase := 0;
        END;
        RETURN ActRedraw;
      END;
    END;
    RETURN ActNone;
  END;

  IF evType = MOUSEUP THEN
    sbDragging := FALSE;
    dragging := FALSE;
    RETURN ActNone;
  END;

  IF evType = KEYDOWN THEN
    shifted := (mods MOD (MOD_SHIFT * 2)) DIV MOD_SHIFT = 1;
    ctrl := ((mods MOD (MOD_CTRL * 2)) DIV MOD_CTRL = 1) OR
            ((mods MOD (MOD_GUI * 2)) DIV MOD_GUI = 1);

    (* Ctrl shortcuts *)
    IF ctrl THEN
      IF key = KEY_UP THEN
        d.cursor := 0;
        d.topRow := 0;
        d.nibblePhase := 0;
        d.binBitPos := 0;
        ClearSelection(d);
        RETURN ActRedraw;
      ELSIF key = KEY_DOWN THEN
        IF FileLen(d) > 0 THEN
          d.cursor := FileLen(d) - 1;
        END;
        d.nibblePhase := 0;
        d.binBitPos := 0;
        ClearSelection(d);
        EnsureVisible(d);
        RETURN ActRedraw;
      ELSIF (key = ORD("s")) OR (key = ORD("S")) THEN
        IF Save(d) THEN END;
        RETURN ActRedraw;
      ELSIF (key = ORD("z")) OR (key = ORD("Z")) THEN
        IF Undo(d) THEN END;
        RETURN ActRedraw;
      ELSIF (key = ORD("y")) OR (key = ORD("Y")) THEN
        IF Redo(d) THEN END;
        RETURN ActRedraw;
      ELSIF ((key = ORD("=")) OR (key = ORD("+"))) AND NOT KeyRepeat() THEN
        RETURN ActZoomIn;
      ELSIF ((key = ORD("-")) OR (key = ORD("_"))) AND NOT KeyRepeat() THEN
        RETURN ActZoomOut;
      ELSIF (key = ORD("f")) OR (key = ORD("F")) THEN
        EnterSearch(d);
        RETURN ActRedraw;
      ELSIF (key = ORD("g")) OR (key = ORD("G")) THEN
        DoFindNext(d);
        RETURN ActRedraw;
      ELSIF (key = ORD("l")) OR (key = ORD("L")) THEN
        EnterGoto(d);
        RETURN ActRedraw;
      ELSIF (key = ORD("c")) OR (key = ORD("C")) THEN
        DoCopy(d);
        RETURN ActRedraw;
      ELSIF (key = ORD("v")) OR (key = ORD("V")) THEN
        DoPaste(d);
        RETURN ActRedraw;
      ELSIF (key = ORD("e")) OR (key = ORD("E")) THEN
        EnterFill(d);
        RETURN ActRedraw;
      ELSIF (key = ORD("r")) OR (key = ORD("R")) THEN
        EnterReplace(d);
        RETURN ActRedraw;
      ELSIF (key = ORD("d")) OR (key = ORD("D")) THEN
        EnterExport(d);
        RETURN ActRedraw;
      ELSIF (key = ORD("b")) OR (key = ORD("B")) THEN
        ToggleHistogram(d);
        RETURN ActRedraw;
      ELSIF (key = ORD("t")) OR (key = ORD("T")) THEN
        ToggleEndianness;
        RETURN ActRedraw;
      ELSIF (key = ORD("i")) OR (key = ORD("I")) THEN
        (*$IF MACOS *)
        mac_show_about(ADR("hexed"), ADR("1.0.0"),
                       ADR("A hex editor built with Modula-2"));
        (*$END *)
        RETURN ActNone;
      END;
      RETURN ActNone;
    END;

    (* Binary mode input *)
    IF d.editMode = ModeBin THEN
      IF key = KEY_ESCAPE THEN
        d.editMode := ModeHex;
        d.binBitPos := 0;
        RETURN ActRedraw;
      ELSIF (key = ORD("0")) OR (key = ORD("1")) THEN
        IF key = ORD("0") THEN
          InputBinBit(d, 0);
        ELSE
          InputBinBit(d, 1);
        END;
        (* Advance to next bit, wrap to next byte at bit 7 *)
        IF d.binBitPos < 7 THEN
          INC(d.binBitPos);
        ELSE
          d.binBitPos := 0;
          IF d.cursor + 1 < FileLen(d) THEN
            INC(d.cursor);
            EnsureVisible(d);
          END;
        END;
        RETURN ActRedraw;
      ELSIF key = KEY_LEFT THEN
        IF d.binBitPos > 0 THEN
          DEC(d.binBitPos);
        ELSE
          (* Wrap to previous byte, bit 7 *)
          IF d.cursor > 0 THEN
            DEC(d.cursor);
            d.binBitPos := 7;
            d.nibblePhase := 0;
            EnsureVisible(d);
          END;
        END;
        RETURN ActRedraw;
      ELSIF key = KEY_RIGHT THEN
        IF d.binBitPos < 7 THEN
          INC(d.binBitPos);
        ELSE
          (* Wrap to next byte, bit 0 *)
          IF d.cursor + 1 < FileLen(d) THEN
            INC(d.cursor);
            d.binBitPos := 0;
            d.nibblePhase := 0;
            EnsureVisible(d);
          END;
        END;
        RETURN ActRedraw;
      ELSIF key = KEY_TAB THEN
        d.editMode := ModeHex;
        d.binBitPos := 0;
        RETURN ActRedraw;
      END;
      (* Up/Down/PgUp/PgDn/Home/End fall through to navigation below *)
    END;

    (* Selection: shift + arrows *)
    IF shifted THEN
      StartSelection(d);
    ELSE
      IF (key = KEY_UP) OR (key = KEY_DOWN) OR
         (key = KEY_LEFT) OR (key = KEY_RIGHT) THEN
        ClearSelection(d);
      END;
    END;

    (* Navigation *)
    IF key = KEY_UP THEN
      MoveCursorUp(d); RETURN ActRedraw;
    ELSIF key = KEY_DOWN THEN
      MoveCursorDown(d); RETURN ActRedraw;
    ELSIF key = KEY_LEFT THEN
      MoveCursorLeft(d); RETURN ActRedraw;
    ELSIF key = KEY_RIGHT THEN
      MoveCursorRight(d); RETURN ActRedraw;
    ELSIF key = KEY_PAGEUP THEN
      PageUp(d); RETURN ActRedraw;
    ELSIF key = KEY_PAGEDOWN THEN
      PageDown(d); RETURN ActRedraw;
    ELSIF key = KEY_HOME THEN
      Home(d); RETURN ActRedraw;
    ELSIF key = KEY_END THEN
      End(d); RETURN ActRedraw;
    ELSIF key = KEY_TAB THEN
      ToggleMode(d); RETURN ActRedraw;
    ELSIF key = KEY_ESCAPE THEN
      ClearSelection(d); RETURN ActRedraw;
    END;

    (* Hex editing via keydown *)
    IF d.editMode = ModeHex THEN
      nibble := KeyToNibble(key);
      IF nibble >= 0 THEN
        InputHexNibble(d, CARDINAL(nibble));
        RETURN ActRedraw;
      END;
    END;

    RETURN ActNone;
  END;

  (* Text input for ASCII mode *)
  IF evType = TEXTINPUT THEN
    IF d.editMode = ModeAscii THEN
      TextInput(textBuf);
      ch := textBuf[0];
      IF (ORD(ch) >= 32) AND (ORD(ch) <= 126) THEN
        InputAscii(d, ch);
        RETURN ActRedraw;
      END;
    END;
    RETURN ActNone;
  END;

  RETURN ActNone;
END HandleEvent;

PROCEDURE KeyToNibble(keyCode: INTEGER): INTEGER;
BEGIN
  IF (keyCode >= ORD("0")) AND (keyCode <= ORD("9")) THEN
    RETURN keyCode - ORD("0");
  ELSIF (keyCode >= ORD("a")) AND (keyCode <= ORD("f")) THEN
    RETURN keyCode - ORD("a") + 10;
  ELSIF (keyCode >= ORD("A")) AND (keyCode <= ORD("F")) THEN
    RETURN keyCode - ORD("A") + 10;
  END;
  RETURN -1;
END KeyToNibble;

BEGIN
  dragging := FALSE;
  dragAnchor := 0;
  sbDragging := FALSE;
  sbDragStartY := 0;
  sbDragStartRow := 0;
  searchMode := FALSE;
  searchLen := 0;
  searchIsHex := TRUE;
  lastLen := 0;
  lastIsHex := TRUE;
  notFound := FALSE;
  gotoMode := FALSE;
  gotoLen := 0;
  gotoError := FALSE;
  fillMode := FALSE;
  fillLen := 0;
  replaceMode := FALSE;
  replacePhase := 0;
  replSearchLen := 0;
  replReplaceLen := 0;
  replIsHex := TRUE;
  replNotFound := FALSE;
  exportMode := FALSE;
  exportLen := 0;
  exportError := FALSE;
END Keymap.

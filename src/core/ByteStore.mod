IMPLEMENTATION MODULE ByteStore;

FROM SYSTEM IMPORT ADDRESS, ADR;
FROM ByteBuf IMPORT Buf, Init AS BufInit, Free AS BufFree,
                     AppendChars, GetByte AS BufGetByte, SetByte AS BufSetByte,
                     DataPtr;
FROM Sys IMPORT m2sys_fopen, m2sys_fclose, m2sys_fread_bytes, m2sys_fwrite_bytes,
                m2sys_file_size, m2sys_fseek;

(* ── Memory backend ─────────────────────────────────── *)

PROCEDURE MemOpen(VAR s: Store): BOOLEAN;
VAR
  hnd: INTEGER;
  tmp: ARRAY [0..4095] OF CHAR;
  n: INTEGER;
BEGIN
  BufInit(s.buf, s.fileLen);

  hnd := m2sys_fopen(ADR(s.filePath), ADR("rb"));
  IF hnd < 0 THEN
    BufFree(s.buf);
    RETURN FALSE;
  END;

  LOOP
    n := m2sys_fread_bytes(hnd, ADR(tmp), 4096);
    IF n <= 0 THEN EXIT; END;
    IF n > 4096 THEN n := 4096; END;
    AppendChars(s.buf, tmp, CARDINAL(n));
  END;
  m2sys_fclose(hnd);
  RETURN TRUE;
END MemOpen;

PROCEDURE MemGetByte(VAR s: Store; off: CARDINAL): CARDINAL;
BEGIN
  RETURN BufGetByte(s.buf, off);
END MemGetByte;

PROCEDURE MemSetByte(VAR s: Store; off: CARDINAL; val: CARDINAL);
BEGIN
  BufSetByte(s.buf, off, val);
  s.dirty := TRUE;
END MemSetByte;

PROCEDURE MemClose(VAR s: Store);
BEGIN
  BufFree(s.buf);
END MemClose;

(* ── Paged backend ──────────────────────────────────── *)

PROCEDURE PagedLoadPage(VAR s: Store; pageNo: CARDINAL; VAR pg: Page);
VAR
  hnd: INTEGER;
  off, n: CARDINAL;
BEGIN
  pg.pageNo := pageNo;
  pg.dirty := FALSE;
  INC(s.accessCt);
  pg.lastUse := s.accessCt;
  off := pageNo * PageSize;

  hnd := m2sys_fopen(ADR(s.filePath), ADR("rb"));
  IF hnd < 0 THEN RETURN; END;

  IF off > 0 THEN
    IF m2sys_fseek(hnd, LONGINT(off), 0) < 0 THEN
      m2sys_fclose(hnd);
      RETURN;
    END;
  END;

  n := CARDINAL(m2sys_fread_bytes(hnd, ADR(pg.data), PageSize));
  WHILE n < PageSize DO
    pg.data[n] := CHR(0);
    INC(n);
  END;
  m2sys_fclose(hnd);
END PagedLoadPage;

PROCEDURE FindLRU(VAR s: Store): CARDINAL;
VAR i, best: CARDINAL;
    bestUse: CARDINAL;
BEGIN
  best := 0;
  bestUse := s.pages[0].lastUse;
  FOR i := 1 TO s.nPages - 1 DO
    IF s.pages[i].lastUse < bestUse THEN
      best := i;
      bestUse := s.pages[i].lastUse;
    END;
  END;
  RETURN best;
END FindLRU;

PROCEDURE FindOrLoadPage(VAR s: Store; pageNo: CARDINAL): CARDINAL;
VAR i, slot: CARDINAL;
BEGIN
  (* Fast path: check last-used slot first (sequential access pattern) *)
  IF (s.nPages > 0) AND (s.pages[s.lastSlot].pageNo = pageNo) THEN
    INC(s.accessCt);
    s.pages[s.lastSlot].lastUse := s.accessCt;
    RETURN s.lastSlot;
  END;
  IF s.nPages > 0 THEN
    FOR i := 0 TO s.nPages - 1 DO
      IF s.pages[i].pageNo = pageNo THEN
        INC(s.accessCt);
        s.pages[i].lastUse := s.accessCt;
        s.lastSlot := i;
        RETURN i;
      END;
    END;
  END;
  IF s.nPages < MaxPages THEN
    slot := s.nPages;
    INC(s.nPages);
  ELSE
    slot := FindLRU(s);
    (* TODO: flush dirty page before eviction *)
  END;
  PagedLoadPage(s, pageNo, s.pages[slot]);
  s.lastSlot := slot;
  RETURN slot;
END FindOrLoadPage;

PROCEDURE PagedGetByte(VAR s: Store; off: CARDINAL): CARDINAL;
VAR pageNo, slot, idx: CARDINAL;
BEGIN
  pageNo := off DIV PageSize;
  idx := off MOD PageSize;
  slot := FindOrLoadPage(s, pageNo);
  RETURN ORD(s.pages[slot].data[idx]);
END PagedGetByte;

PROCEDURE PagedSetByte(VAR s: Store; off: CARDINAL; val: CARDINAL);
VAR pageNo, slot, idx: CARDINAL;
BEGIN
  pageNo := off DIV PageSize;
  idx := off MOD PageSize;
  slot := FindOrLoadPage(s, pageNo);
  s.pages[slot].data[idx] := CHR(val MOD 256);
  s.pages[slot].dirty := TRUE;
  s.dirty := TRUE;
END PagedSetByte;

PROCEDURE PagedClose(VAR s: Store);
BEGIN
  s.nPages := 0;
  s.accessCt := 0;
END PagedClose;

(* ── Public interface ────────────────────────────────── *)

PROCEDURE CopyPath(VAR dst: ARRAY OF CHAR; src: ARRAY OF CHAR);
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE (i < HIGH(src)) AND (i < HIGH(dst)) AND (src[i] # 0C) DO
    dst[i] := src[i];
    INC(i);
  END;
  IF i <= HIGH(dst) THEN dst[i] := 0C; END;
END CopyPath;

PROCEDURE Open(VAR s: Store; path: ARRAY OF CHAR): BOOLEAN;
VAR sz64: LONGINT;
BEGIN
  CopyPath(s.filePath, path);
  sz64 := m2sys_file_size(ADR(s.filePath));
  IF sz64 < 0 THEN RETURN FALSE; END;
  IF sz64 > LONGINT(MAX(CARDINAL)) THEN RETURN FALSE; END;
  s.fileLen := CARDINAL(sz64);
  s.dirty := FALSE;
  s.nPages := 0;
  s.accessCt := 0;
  s.lastSlot := 0;

  IF s.fileLen <= ThresholdLen THEN
    s.mode := ModeMemory;
    RETURN MemOpen(s);
  ELSE
    s.mode := ModePaged;
    RETURN TRUE;
  END;
END Open;

PROCEDURE Close(VAR s: Store);
BEGIN
  IF s.mode = ModeMemory THEN
    MemClose(s);
  ELSE
    PagedClose(s);
  END;
  s.fileLen := 0;
END Close;

PROCEDURE Len(VAR s: Store): CARDINAL;
BEGIN
  RETURN s.fileLen;
END Len;

PROCEDURE GetByte(VAR s: Store; off: CARDINAL): CARDINAL;
BEGIN
  IF off >= s.fileLen THEN RETURN 0; END;
  IF s.mode = ModeMemory THEN
    RETURN MemGetByte(s, off);
  ELSE
    RETURN PagedGetByte(s, off);
  END;
END GetByte;

PROCEDURE SetByte(VAR s: Store; off: CARDINAL; val: CARDINAL);
BEGIN
  IF off >= s.fileLen THEN RETURN; END;
  IF s.mode = ModeMemory THEN
    MemSetByte(s, off, val);
  ELSE
    PagedSetByte(s, off, val);
  END;
END SetByte;

PROCEDURE ReadBlock(VAR s: Store; off: CARDINAL;
                    VAR buf: ARRAY OF CHAR; maxLen: CARDINAL): CARDINAL;
VAR
  avail, count, i: CARDINAL;
  pageNo, slot, idx, inPage: CARDINAL;
BEGIN
  IF off >= s.fileLen THEN RETURN 0; END;
  avail := s.fileLen - off;
  IF maxLen < avail THEN count := maxLen ELSE count := avail END;
  IF count = 0 THEN RETURN 0; END;

  IF s.mode = ModeMemory THEN
    FOR i := 0 TO count - 1 DO
      buf[i] := CHR(BufGetByte(s.buf, off + i));
    END;
  ELSE
    (* Paged: copy from current page up to page boundary *)
    pageNo := off DIV PageSize;
    idx := off MOD PageSize;
    inPage := PageSize - idx;
    IF count > inPage THEN count := inPage; END;
    slot := FindOrLoadPage(s, pageNo);
    FOR i := 0 TO count - 1 DO
      buf[i] := s.pages[slot].data[idx + i];
    END;
  END;
  RETURN count;
END ReadBlock;

PROCEDURE IsDirty(VAR s: Store): BOOLEAN;
BEGIN
  RETURN s.dirty;
END IsDirty;

PROCEDURE MemFlush(VAR s: Store): BOOLEAN;
VAR
  hnd: INTEGER;
  tmp: ARRAY [0..4095] OF CHAR;
  pos, remaining, chunk, i: CARDINAL;
BEGIN
  hnd := m2sys_fopen(ADR(s.filePath), ADR("wb"));
  IF hnd < 0 THEN RETURN FALSE; END;

  pos := 0;
  remaining := s.fileLen;
  WHILE remaining > 0 DO
    IF remaining > 4096 THEN chunk := 4096 ELSE chunk := remaining END;
    FOR i := 0 TO chunk - 1 DO
      tmp[i] := CHR(BufGetByte(s.buf, pos + i));
    END;
    IF m2sys_fwrite_bytes(hnd, ADR(tmp), INTEGER(chunk)) # INTEGER(chunk) THEN
      m2sys_fclose(hnd);
      RETURN FALSE;
    END;
    INC(pos, chunk);
    DEC(remaining, chunk);
  END;
  m2sys_fclose(hnd);
  s.dirty := FALSE;
  RETURN TRUE;
END MemFlush;

PROCEDURE PagedFlush(VAR s: Store): BOOLEAN;
VAR
  hnd: INTEGER;
  i, pgOff: CARDINAL;
BEGIN
  (* Open file once, seek to each dirty page, write, then close *)
  hnd := m2sys_fopen(ADR(s.filePath), ADR("r+b"));
  IF hnd < 0 THEN RETURN FALSE; END;

  FOR i := 0 TO s.nPages - 1 DO
    IF s.pages[i].dirty THEN
      pgOff := s.pages[i].pageNo * PageSize;
      IF m2sys_fseek(hnd, LONGINT(pgOff), 0) < 0 THEN
        m2sys_fclose(hnd);
        RETURN FALSE;
      END;
      IF m2sys_fwrite_bytes(hnd, ADR(s.pages[i].data), PageSize) # PageSize THEN
        m2sys_fclose(hnd);
        RETURN FALSE;
      END;
      s.pages[i].dirty := FALSE;
    END;
  END;

  m2sys_fclose(hnd);
  s.dirty := FALSE;
  RETURN TRUE;
END PagedFlush;

PROCEDURE Flush(VAR s: Store): BOOLEAN;
BEGIN
  IF s.mode = ModeMemory THEN
    RETURN MemFlush(s);
  ELSE
    RETURN PagedFlush(s);
  END;
END Flush;

END ByteStore.

IMPLEMENTATION MODULE Search;

FROM Doc IMPORT Document, FileLen, ReadBlock;

PROCEDURE HexCharVal(ch: CHAR; VAR val: CARDINAL): BOOLEAN;
BEGIN
  IF (ch >= "0") AND (ch <= "9") THEN
    val := ORD(ch) - ORD("0"); RETURN TRUE;
  ELSIF (ch >= "a") AND (ch <= "f") THEN
    val := ORD(ch) - ORD("a") + 10; RETURN TRUE;
  ELSIF (ch >= "A") AND (ch <= "F") THEN
    val := ORD(ch) - ORD("A") + 10; RETURN TRUE;
  END;
  RETURN FALSE;
END HexCharVal;

(* Parse hex string into byte array. Returns number of bytes. *)
PROCEDURE ParseHex(pat: ARRAY OF CHAR; patLen: INTEGER;
                   VAR bytes: ARRAY OF CARDINAL): INTEGER;
VAR i, n: INTEGER;
    hi, lo: CARDINAL;
BEGIN
  n := 0;
  i := 0;
  WHILE (i + 1 < patLen) AND (n <= INTEGER(HIGH(bytes))) DO
    IF HexCharVal(pat[i], hi) AND HexCharVal(pat[i+1], lo) THEN
      bytes[n] := hi * 16 + lo;
      INC(n);
    END;
    INC(i, 2);
  END;
  RETURN n;
END ParseHex;

(* Convert pattern bytes to CHAR array for block comparison *)
PROCEDURE MakePatChars(VAR bytes: ARRAY OF CARDINAL; nBytes: INTEGER;
                       VAR patChars: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  FOR i := 0 TO nBytes - 1 DO
    patChars[i] := CHR(bytes[i]);
  END;
END MakePatChars;

(* Search a block for pattern. Returns offset within block or -1. *)
PROCEDURE ScanBlock(VAR block: ARRAY OF CHAR; blockLen: CARDINAL;
                    VAR patChars: ARRAY OF CHAR; nBytes: INTEGER): INTEGER;
VAR i: CARDINAL;
    j: INTEGER;
    limit: CARDINAL;
    matched: BOOLEAN;
BEGIN
  IF blockLen < CARDINAL(nBytes) THEN RETURN -1; END;
  limit := blockLen - CARDINAL(nBytes);
  FOR i := 0 TO limit DO
    matched := TRUE;
    j := 0;
    WHILE (j < nBytes) AND matched DO
      IF block[i + CARDINAL(j)] # patChars[j] THEN
        matched := FALSE;
      END;
      INC(j);
    END;
    IF matched THEN RETURN INTEGER(i); END;
  END;
  RETURN -1;
END ScanBlock;

PROCEDURE FindNext(VAR d: Document; pat: ARRAY OF CHAR; patLen: INTEGER;
                   isHex: BOOLEAN; fromOff: CARDINAL;
                   VAR foundOff, foundLen: CARDINAL): BOOLEAN;
VAR
  bytes: ARRAY [0..63] OF CARDINAL;
  patChars: ARRAY [0..63] OF CHAR;
  block: ARRAY [0..4095] OF CHAR;
  nBytes: INTEGER;
  fileSize: CARDINAL;
  pos, startPos, readOff: CARDINAL;
  n, hit: INTEGER;
  i: INTEGER;
  wrapped: BOOLEAN;
  overlap: CARDINAL;
BEGIN
  fileSize := FileLen(d);
  IF (fileSize = 0) OR (patLen = 0) THEN RETURN FALSE; END;

  IF isHex THEN
    nBytes := ParseHex(pat, patLen, bytes);
    IF nBytes = 0 THEN RETURN FALSE; END;
  ELSE
    nBytes := patLen;
    IF nBytes > 64 THEN nBytes := 64; END;
    FOR i := 0 TO nBytes - 1 DO
      bytes[i] := ORD(pat[i]);
    END;
  END;

  IF CARDINAL(nBytes) > fileSize THEN RETURN FALSE; END;

  MakePatChars(bytes, nBytes, patChars);

  IF fromOff + 1 < fileSize THEN
    startPos := fromOff + 1;
  ELSE
    startPos := 0;
  END;

  overlap := CARDINAL(nBytes) - 1;
  pos := startPos;
  wrapped := FALSE;

  LOOP
    (* Determine how many bytes to read *)
    readOff := ReadBlock(d, pos, block, 4096);
    IF readOff = 0 THEN
      (* At or past end of file *)
      IF wrapped THEN RETURN FALSE; END;
      pos := 0;
      wrapped := TRUE;
      IF pos >= startPos THEN RETURN FALSE; END;
    ELSE
      (* If wrapped, don't scan past startPos *)
      IF wrapped AND (pos + readOff > startPos + CARDINAL(nBytes) - 1) THEN
        readOff := startPos + CARDINAL(nBytes) - 1 - pos;
        IF readOff = 0 THEN RETURN FALSE; END;
      END;

      hit := ScanBlock(block, readOff, patChars, nBytes);
      IF hit >= 0 THEN
        foundOff := pos + CARDINAL(hit);
        foundLen := CARDINAL(nBytes);
        RETURN TRUE;
      END;

      (* Advance past this block, keeping overlap for boundary matches *)
      IF readOff > overlap THEN
        INC(pos, readOff - overlap);
      ELSE
        INC(pos, 1);
      END;

      (* Check for wrap *)
      IF pos + CARDINAL(nBytes) > fileSize THEN
        IF wrapped THEN RETURN FALSE; END;
        pos := 0;
        wrapped := TRUE;
      END;
      IF wrapped AND (pos >= startPos) THEN
        RETURN FALSE;
      END;
    END;
  END;
END FindNext;

END Search.

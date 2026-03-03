IMPLEMENTATION MODULE HistogramState;

VAR
  hShow: BOOLEAN;
  freq: ARRAY [0..255] OF CARDINAL;
  maxFreq: CARDINAL;
  totalBytes: CARDINAL;

PROCEDURE SetShowHistogram(on: BOOLEAN);
BEGIN
  hShow := on;
END SetShowHistogram;

PROCEDURE IsShowHistogram(): BOOLEAN;
BEGIN
  RETURN hShow;
END IsShowHistogram;

PROCEDURE SetFrequency(byteVal: CARDINAL; count: CARDINAL);
BEGIN
  IF byteVal <= 255 THEN
    freq[byteVal] := count;
  END;
END SetFrequency;

PROCEDURE GetFrequency(byteVal: CARDINAL): CARDINAL;
BEGIN
  IF byteVal <= 255 THEN
    RETURN freq[byteVal];
  END;
  RETURN 0;
END GetFrequency;

PROCEDURE ClearFrequencies;
VAR i: CARDINAL;
BEGIN
  FOR i := 0 TO 255 DO
    freq[i] := 0;
  END;
  maxFreq := 0;
  totalBytes := 0;
END ClearFrequencies;

PROCEDURE SetMaxFrequency(m: CARDINAL);
BEGIN
  maxFreq := m;
END SetMaxFrequency;

PROCEDURE GetMaxFrequency(): CARDINAL;
BEGIN
  RETURN maxFreq;
END GetMaxFrequency;

PROCEDURE SetTotalBytes(t: CARDINAL);
BEGIN
  totalBytes := t;
END SetTotalBytes;

PROCEDURE GetTotalBytes(): CARDINAL;
BEGIN
  RETURN totalBytes;
END GetTotalBytes;

BEGIN
  hShow := FALSE;
  maxFreq := 0;
  totalBytes := 0;
  ClearFrequencies;
END HistogramState.

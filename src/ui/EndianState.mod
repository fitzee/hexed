IMPLEMENTATION MODULE EndianState;

VAR
  endian: Endianness;

PROCEDURE SetEndianness(e: Endianness);
BEGIN
  endian := e;
END SetEndianness;

PROCEDURE GetEndianness(): Endianness;
BEGIN
  RETURN endian;
END GetEndianness;

PROCEDURE ToggleEndianness;
BEGIN
  IF endian = LittleEndian THEN
    endian := BigEndian;
  ELSE
    endian := LittleEndian;
  END;
END ToggleEndianness;

PROCEDURE IsLittleEndian(): BOOLEAN;
BEGIN
  RETURN endian = LittleEndian;
END IsLittleEndian;

BEGIN
  endian := LittleEndian;
END EndianState.

IMPLEMENTATION MODULE Theme;

PROCEDURE Init;
BEGIN
  Dark.bgPrimary.r   :=  30; Dark.bgPrimary.g   :=  30; Dark.bgPrimary.b   :=  36; Dark.bgPrimary.a   := 255;
  Dark.bgAlt.r       :=  36; Dark.bgAlt.g       :=  36; Dark.bgAlt.b       :=  44; Dark.bgAlt.a       := 255;
  Dark.bgStatusBar.r :=  22; Dark.bgStatusBar.g :=  22; Dark.bgStatusBar.b :=  28; Dark.bgStatusBar.a := 255;
  Dark.fgOffset.r    := 100; Dark.fgOffset.g    := 110; Dark.fgOffset.b    := 130; Dark.fgOffset.a    := 255;
  Dark.fgHex.r       := 220; Dark.fgHex.g       := 225; Dark.fgHex.b       := 235; Dark.fgHex.a       := 255;
  Dark.fgAscii.r     := 200; Dark.fgAscii.g     := 205; Dark.fgAscii.b     := 215; Dark.fgAscii.a     := 255;
  Dark.fgNonPrint.r  :=  70; Dark.fgNonPrint.g  :=  75; Dark.fgNonPrint.b  :=  85; Dark.fgNonPrint.a  := 255;
  Dark.fgStatus.r    := 190; Dark.fgStatus.g    := 195; Dark.fgStatus.b    := 210; Dark.fgStatus.a    := 255;
  Dark.fgStatusDim.r := 110; Dark.fgStatusDim.g := 115; Dark.fgStatusDim.b := 130; Dark.fgStatusDim.a := 255;
  Dark.cursorBg.r    :=  60; Dark.cursorBg.g    := 130; Dark.cursorBg.b    := 220; Dark.cursorBg.a    := 255;
  Dark.cursorFg.r    := 255; Dark.cursorFg.g    := 255; Dark.cursorFg.b    := 255; Dark.cursorFg.a    := 255;
  Dark.selectionBg.r :=  50; Dark.selectionBg.g :=  80; Dark.selectionBg.b := 140; Dark.selectionBg.a := 100;
  Dark.dirty.r       := 240; Dark.dirty.g       := 180; Dark.dirty.b       :=  60; Dark.dirty.a       := 255;
  Dark.separator.r   :=  55; Dark.separator.g   :=  58; Dark.separator.b   :=  68; Dark.separator.a   := 255;
  Dark.helpHeader.r  := 230; Dark.helpHeader.g  := 160; Dark.helpHeader.b  :=  50; Dark.helpHeader.a  := 255;
  Dark.helpKey.r     := 210; Dark.helpKey.g     := 190; Dark.helpKey.b     := 110; Dark.helpKey.a     := 255;
  Dark.helpDesc.r    := 140; Dark.helpDesc.g    := 135; Dark.helpDesc.b    := 120; Dark.helpDesc.a    := 255;
  Dark.sbTrack.r     :=  22; Dark.sbTrack.g     :=  22; Dark.sbTrack.b     :=  28; Dark.sbTrack.a     := 255;
  Dark.sbThumb.r     :=  80; Dark.sbThumb.g     :=  85; Dark.sbThumb.b     := 100; Dark.sbThumb.a     := 255;
END Init;

END Theme.

unit GifAnim;

{ ตัวเขียนภาพเคลื่อนไหว GIF89a แบบทีละเฟรม (ไม่ต้องเก็บทุกเฟรมไว้ในหน่วยความจำ)
  - แต่ละเฟรมเขียนเฉพาะกรอบที่เปลี่ยนจากเฟรมก่อน (disposal = ไม่ลบ) ไฟล์จึงเล็ก
  - ตารางสีประจำเฟรม: สีจริงถ้าไม่เกิน 256 สี ไม่งั้นใช้ชุดสี 6x7x6 (252 สี)
  - LZW และการแบ่งบล็อกดัดแปลงจาก GifWriter ของโปรเจกต์ Create marble Pixel SDL3 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  TGifStream = class
  private
    FS: TFileStream;
    FW, FH: Integer;
    FPrev: array of LongWord;     // สี $RRGGBB ของเฟรมก่อน
    FHasPrev: Boolean;
    FIdx: array of Byte;
  public
    { loop = 0: วนไม่รู้จบ }
    constructor Create(const FileName: string; W, H, Loop: Integer);
    destructor Destroy; override;
    { pixels: แถวละ pitch ไบต์ รูปแบบ ARGB8888 (หน่วยความจำ B G R A) }
    procedure AddFrame(pixels: Pointer; pitch: Integer; delayCs: Integer);
    procedure Finish;
  end;

implementation

{ ---------- บิต -> บล็อกย่อย 255 ไบต์ ---------- }

type
  TBitWriter = record
    S: TStream;
    Acc: LongWord;
    NBits: Integer;
    Block: array[0..254] of Byte;
    BLen: Integer;
  end;

procedure BWFlushBlock(var B: TBitWriter);
begin
  if B.BLen > 0 then
  begin
    B.S.WriteByte(B.BLen);
    B.S.WriteBuffer(B.Block[0], B.BLen);
    B.BLen := 0;
  end;
end;

procedure BWPutByte(var B: TBitWriter; v: Byte);
begin
  B.Block[B.BLen] := v;
  Inc(B.BLen);
  if B.BLen = 255 then BWFlushBlock(B);
end;

procedure BWWrite(var B: TBitWriter; Code, Size: Integer);
begin
  B.Acc := B.Acc or (LongWord(Code) shl B.NBits);
  Inc(B.NBits, Size);
  while B.NBits >= 8 do
  begin
    BWPutByte(B, B.Acc and $FF);
    B.Acc := B.Acc shr 8;
    Dec(B.NBits, 8);
  end;
end;

procedure BWFinish(var B: TBitWriter);
begin
  if B.NBits > 0 then BWPutByte(B, B.Acc and $FF);
  B.Acc := 0;
  B.NBits := 0;
  BWFlushBlock(B);
  B.S.WriteByte(0);
end;

{ ---------- LZW ---------- }

const
  HSIZE = 16411;

procedure LzwEncode(S: TStream; const Idx: array of Byte; Count, MinCode: Integer);
var
  B: TBitWriter;
  HKey: array of LongInt;
  HCode: array of Word;
  ClearCode, CodeSize, MaxCode, Cur, k, key, found, i: Integer;
  h: LongWord;
begin
  SetLength(HKey, HSIZE);
  SetLength(HCode, HSIZE);
  FillChar(HKey[0], HSIZE * SizeOf(LongInt), $FF);
  FillChar(B, SizeOf(B), 0);
  B.S := S;
  S.WriteByte(MinCode);
  ClearCode := 1 shl MinCode;
  CodeSize := MinCode + 1;
  MaxCode := ClearCode + 1;
  BWWrite(B, ClearCode, CodeSize);
  Cur := Idx[0];
  for i := 1 to Count - 1 do
  begin
    k := Idx[i];
    key := (Cur shl 8) or k;
    h := LongWord((QWord(LongWord(key)) * 2654435761) mod HSIZE);
    found := -1;
    while HKey[h] <> -1 do
    begin
      if HKey[h] = key then
      begin
        found := HCode[h];
        Break;
      end;
      Inc(h);
      if h = HSIZE then h := 0;
    end;
    if found >= 0 then
      Cur := found
    else
    begin
      BWWrite(B, Cur, CodeSize);
      Inc(MaxCode);
      HKey[h] := key;
      HCode[h] := MaxCode;
      if MaxCode >= (1 shl CodeSize) then Inc(CodeSize);
      if MaxCode = 4095 then
      begin
        BWWrite(B, ClearCode, CodeSize);
        FillChar(HKey[0], HSIZE * SizeOf(LongInt), $FF);
        CodeSize := MinCode + 1;
        MaxCode := ClearCode + 1;
      end;
      Cur := k;
    end;
  end;
  BWWrite(B, Cur, CodeSize);
  BWWrite(B, ClearCode, CodeSize);
  BWWrite(B, ClearCode + 1, MinCode + 1);
  BWFinish(B);
end;

procedure WriteWord(S: TStream; v: Integer);
begin
  S.WriteByte(v and $FF);
  S.WriteByte((v shr 8) and $FF);
end;

{ ---------- TGifStream ---------- }

constructor TGifStream.Create(const FileName: string; W, H, Loop: Integer);
begin
  inherited Create;
  FW := W;
  FH := H;
  SetLength(FPrev, W * H);
  SetLength(FIdx, W * H);
  FS := TFileStream.Create(FileName, fmCreate);
  FS.WriteBuffer(PAnsiChar('GIF89a')^, 6);
  WriteWord(FS, W);
  WriteWord(FS, H);
  FS.WriteByte(0);        // ไม่มีตารางสีรวม (ใช้ตารางประจำเฟรม)
  FS.WriteByte(0);
  FS.WriteByte(0);
  { NETSCAPE2.0: วนซ้ำ }
  FS.WriteByte($21); FS.WriteByte($FF); FS.WriteByte(11);
  FS.WriteBuffer(PAnsiChar('NETSCAPE2.0')^, 11);
  FS.WriteByte(3); FS.WriteByte(1);
  WriteWord(FS, Loop);
  FS.WriteByte(0);
end;

destructor TGifStream.Destroy;
begin
  Finish;
  inherited Destroy;
end;

procedure TGifStream.Finish;
begin
  if FS = nil then Exit;
  FS.WriteByte($3B);
  FreeAndNil(FS);
end;

procedure TGifStream.AddFrame(pixels: Pointer; pitch: Integer; delayCs: Integer);
const
  CHASH = 1031;
var
  x, y, x0, y0, x1, y1, bw, bh, i, k, nc, sizeField, tableSize, minCode: Integer;
  row: PLongWord;
  c: LongWord;
  exact: Boolean;
  CKey: array[0..CHASH - 1] of LongInt;
  CIdx: array[0..CHASH - 1] of Byte;
  Pal: array[0..255] of LongWord;

  function Px(xx, yy: Integer): LongWord; inline;
  begin
    Result := PLongWord(PByte(pixels) + yy * pitch + xx * 4)^ and $FFFFFF;
  end;

  function FindOrAdd(col: LongWord): Integer;
  var
    kk: Integer;
  begin
    kk := (col * 2654435761) mod CHASH;
    while CKey[kk] <> 0 do
    begin
      if CKey[kk] = LongInt(col) + 1 then Exit(CIdx[kk]);
      Inc(kk);
      if kk = CHASH then kk := 0;
    end;
    if nc >= 256 then Exit(-1);
    CKey[kk] := LongInt(col) + 1;
    CIdx[kk] := nc;
    Pal[nc] := col;
    Inc(nc);
    Result := nc - 1;
  end;

  { ชุดสีสำรอง 6 x 7 x 6 }
  function Uniform(col: LongWord): Integer; inline;
  begin
    Result := (((col shr 16) and $FF) * 6 div 256) * 42 +
              (((col shr 8) and $FF) * 7 div 256) * 6 +
              ((col and $FF) * 6 div 256);
  end;

begin
  if FS = nil then Exit;

  { 1. กรอบที่เปลี่ยนจากเฟรมก่อน }
  x0 := 0; y0 := 0; x1 := FW - 1; y1 := FH - 1;
  if FHasPrev then
  begin
    x0 := FW; y0 := FH; x1 := -1; y1 := -1;
    for y := 0 to FH - 1 do
    begin
      row := PLongWord(PByte(pixels) + y * pitch);
      for x := 0 to FW - 1 do
        if (row[x] and $FFFFFF) <> FPrev[y * FW + x] then
        begin
          if x < x0 then x0 := x;
          if x > x1 then x1 := x;
          if y < y0 then y0 := y;
          if y > y1 then y1 := y;
        end;
    end;
    if x1 < 0 then
    begin
      { ไม่มีอะไรเปลี่ยน: เขียนจุดเดียวเพื่อเก็บเวลา }
      x0 := 0; y0 := 0; x1 := 0; y1 := 0;
    end;
  end;
  bw := x1 - x0 + 1;
  bh := y1 - y0 + 1;

  { 2. ตารางสี }
  FillChar(CKey, SizeOf(CKey), 0);
  nc := 0;
  exact := True;
  i := 0;
  for y := y0 to y1 do
    for x := x0 to x1 do
    begin
      k := FindOrAdd(Px(x, y));
      if k < 0 then
      begin
        exact := False;
        Break;
      end;
      FIdx[i] := k;
      Inc(i);
    end;
  if not exact then
  begin
    nc := 252;
    for k := 0 to 251 do
      Pal[k] := (((k div 42) * 255 div 5) shl 16) or ((((k div 6) mod 7) * 255 div 6) shl 8) or ((k mod 6) * 255 div 5);
    i := 0;
    for y := y0 to y1 do
      for x := x0 to x1 do
      begin
        FIdx[i] := Uniform(Px(x, y));
        Inc(i);
      end;
  end;
  sizeField := 0;
  while (2 shl sizeField) < nc do Inc(sizeField);
  tableSize := 2 shl sizeField;
  minCode := Max(2, sizeField + 1);

  { 3. เขียนเฟรม: GCE (disposal 1 = คงภาพเดิมไว้), descriptor + ตารางสีประจำเฟรม, ข้อมูล LZW }
  FS.WriteByte($21); FS.WriteByte($F9); FS.WriteByte(4);
  FS.WriteByte(1 shl 2);
  WriteWord(FS, Max(2, delayCs));
  FS.WriteByte(0);
  FS.WriteByte(0);
  FS.WriteByte($2C);
  WriteWord(FS, x0); WriteWord(FS, y0);
  WriteWord(FS, bw); WriteWord(FS, bh);
  FS.WriteByte($80 or sizeField);
  for k := 0 to tableSize - 1 do
    if k < nc then
    begin
      FS.WriteByte((Pal[k] shr 16) and $FF);
      FS.WriteByte((Pal[k] shr 8) and $FF);
      FS.WriteByte(Pal[k] and $FF);
    end
    else
    begin
      FS.WriteByte(0); FS.WriteByte(0); FS.WriteByte(0);
    end;
  LzwEncode(FS, FIdx, bw * bh, minCode);

  { 4. จำภาพไว้เทียบเฟรมถัดไป (ภาพที่ผู้ชมเห็นจริง) }
  if exact then
  begin
    for y := y0 to y1 do
      for x := x0 to x1 do
        FPrev[y * FW + x] := Px(x, y);
  end
  else
  begin
    i := 0;
    for y := y0 to y1 do
      for x := x0 to x1 do
      begin
        FPrev[y * FW + x] := Pal[FIdx[i]];
        Inc(i);
      end;
  end;
  FHasPrev := True;
end;

end.

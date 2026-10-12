unit Gfx;

{ เครื่องมือวาดพื้นฐานบน SDL_Renderer: สี, เส้น, สามเหลี่ยม, วงโค้ง, สี่เหลี่ยมมุมมน, ป้าย pill }

{$mode objfpc}{$H+}

interface

uses
  SDL3;

type
  TPt = record
    x, y: Single;
  end;

  TPtArr = array of TPt;

  TRgb = record
    r, g, b: Byte;
  end;

  { ธีมสี: สีเทาทั้งหมดของ UI ไล่ระหว่าง paper (พื้น) กับ ink (ตัวหนังสือ/เส้น)
    และสีส้มที่ใช้เน้นจะเปลี่ยนเป็น accent ของธีม }
  TTheme = record
    name: string;
    paper, ink, accent: TRgb;
  end;

const
  THEMES: array[0..11] of TTheme = (
    (name: 'Paper';           paper: (r: 252; g: 252; b: 250); ink: (r: 22;  g: 22;  b: 22);  accent: (r: 220; g: 90;  b: 20)),
    (name: 'Dark';            paper: (r: 30;  g: 32;  b: 36);  ink: (r: 226; g: 226; b: 222); accent: (r: 255; g: 145; b: 60)),
    (name: 'Blueprint';       paper: (r: 20;  g: 60;  b: 115); ink: (r: 232; g: 242; b: 255); accent: (r: 255; g: 212; b: 80)),
    (name: 'Sepia';           paper: (r: 244; g: 234; b: 214); ink: (r: 72;  g: 50;  b: 30);  accent: (r: 190; g: 80;  b: 40)),
    (name: 'Solarized Light'; paper: (r: 253; g: 246; b: 227); ink: (r: 7;   g: 54;  b: 66);  accent: (r: 203; g: 75;  b: 22)),
    (name: 'Solarized Dark';  paper: (r: 0;   g: 43;  b: 54);  ink: (r: 238; g: 232; b: 213); accent: (r: 181; g: 137; b: 0)),
    (name: 'Terminal';        paper: (r: 8;   g: 16;  b: 10);  ink: (r: 95;  g: 255; b: 130); accent: (r: 255; g: 200; b: 0)),
    (name: 'Midnight';        paper: (r: 26;  g: 22;  b: 46);  ink: (r: 222; g: 212; b: 255); accent: (r: 255; g: 110; b: 200)),
    (name: 'Mint';            paper: (r: 236; g: 248; b: 242); ink: (r: 18;  g: 72;  b: 62);  accent: (r: 0;   g: 150; b: 120)),
    (name: 'High Contrast';   paper: (r: 0;   g: 0;   b: 0);   ink: (r: 255; g: 255; b: 255); accent: (r: 255; g: 255; b: 0)),
    (name: 'Nord';            paper: (r: 46;  g: 52;  b: 64);  ink: (r: 236; g: 239; b: 244); accent: (r: 136; g: 192; b: 208)),
    (name: 'Rose';            paper: (r: 255; g: 240; b: 244); ink: (r: 92;  g: 30;  b: 52);  accent: (r: 220; g: 60;  b: 110)));

var
  ThemeIdx: Integer = 2;          // ค่าตั้งต้น = Blueprint
  { บันทึกเป็น SVG: ระหว่าง SvgBegin..SvgEnd ทุกคำสั่งวาดจะเขียนเป็นรูปเวกเตอร์แทนการวาดบนจอ }
  SvgOn: Boolean = False;

var
  Ren: PSDL_Renderer;

function Pt(x, y: Single): TPt;
procedure SetTheme(i: Integer);
function FindTheme(const name: string): Integer;
{ สีของ UI: ผ่านธีม }
procedure Col(r, g, b: Byte);
{ สีตามจริง (สีที่ผู้ใช้เลือก: สีทา, ตัวอย่างสี) }
procedure ColRaw(r, g, b: Byte);
{ สีของเอกสาร: ถ้ายังเป็นค่าตั้งต้นให้ตามธีม ถ้าผู้ใช้ตั้งเองใช้ตามจริง }
procedure ColDoc(const c, def: TRgb);
procedure Ink;
procedure Paper;
procedure Tri(x1, y1, x2, y2, x3, y3: Single);
procedure Quad(const a, b, c, d: TPt);
procedure Flush;
procedure Txt(x, y: Single; const s: string);
procedure Line(x1, y1, x2, y2: Single);
procedure ThickLine(x1, y1, x2, y2, w: Single);
procedure Disc(cx, cy, r: Single);
procedure ArcBand(cx, cy, r1, r2, a0, a1: Single);
procedure ArcLine(cx, cy, r, a0, a1: Single);
procedure FillRect(x, y, w, h: Single);
procedure StrokeRect(x, y, w, h: Single);
procedure FillRoundRect(x, y, w, h, rad: Single);
procedure StrokeRoundRect(x, y, w, h, rad: Single);
function Pill(x, y: Single; const s: string; filled: Boolean): Single;
procedure DashedCircle(cx, cy, r: Single);
procedure DashedLine(x1, y1, x2, y2: Single);
procedure Panel(x, y, w, h: Single);
procedure SetClip(x, y, w, h: Integer);
procedure ClearClip;
{ เส้นจุด (ตารางแบบ DASH) }
procedure DotLine(x1, y1, x2, y2: Single);

{ ---- SVG ---- }
procedure SvgBegin(x, y, w, h: Single);
function SvgEnd(const FileName: string): Boolean;
{ รูปหลายเหลี่ยม (เติมสีแบบ even-odd ได้) ใช้ตอนบันทึก SVG แทนการเติมทีละแถว }
procedure SvgPolygon(const P: TPtArr; count: Integer; evenOdd: Boolean);
{ ภาพพื้นหลัง: อ้างถึงไฟล์ภาพ หมุนรอบจุดกลาง }
procedure SvgImage(const path: string; x, y, w, h, angle, opacity: Single);

implementation

uses
  Classes, SysUtils, Math;

var
  Verts: array of TSDL_Vertex;
  VertN: Integer = 0;
  CurCol: TSDL_FColor;
  CurHex: string = '#000000';
  SvgL: TStringList = nil;
  SvgFS: TFormatSettings;

{ ---------- SVG helpers ---------- }

function N(v: Single): string;
begin
  Result := FormatFloat('0.##', v, SvgFS);
end;

procedure Emit(const s: string);
begin
  if SvgL <> nil then SvgL.Add('  ' + s);
end;

function Esc(const s: string): string;
begin
  Result := StringReplace(s, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

function StrokeAttr(w: Single): string;
begin
  Result := Format('fill="none" stroke="%s" stroke-width="%s"', [CurHex, N(w)]);
end;

procedure SvgBegin(x, y, w, h: Single);
begin
  SvgFS := DefaultFormatSettings;
  SvgFS.DecimalSeparator := '.';
  FreeAndNil(SvgL);
  SvgL := TStringList.Create;
  SvgL.Add('<?xml version="1.0" encoding="UTF-8"?>');
  SvgL.Add(Format('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" ' +
    'width="%s" height="%s" viewBox="%s %s %s %s">', [N(w), N(h), N(x), N(y), N(w), N(h)]));
  SvgL.Add('  <!-- Belt and Pulley Path - vector export -->');
  VertN := 0;
  SvgOn := True;
end;

function SvgEnd(const FileName: string): Boolean;
begin
  Result := False;
  SvgOn := False;
  if SvgL = nil then Exit;
  SvgL.Add('</svg>');
  try
    SvgL.SaveToFile(FileName);
    Result := True;
  finally
    FreeAndNil(SvgL);
  end;
end;

procedure SvgPolygon(const P: TPtArr; count: Integer; evenOdd: Boolean);
var
  i: Integer;
  d, rule: string;
begin
  if (not SvgOn) or (count < 3) then Exit;
  d := 'M' + N(P[0].x) + ' ' + N(P[0].y);
  for i := 1 to count - 1 do
    d := d + ' L' + N(P[i].x) + ' ' + N(P[i].y);
  if evenOdd then rule := 'evenodd' else rule := 'nonzero';
  Emit(Format('<path d="%s Z" fill="%s" fill-rule="%s"/>', [d, CurHex, rule]));
end;

procedure SvgImage(const path: string; x, y, w, h, angle, opacity: Single);
var
  href: string;
begin
  if not SvgOn then Exit;
  href := 'file:///' + StringReplace(path, '\', '/', [rfReplaceAll]);
  Emit(Format('<image xlink:href="%s" href="%s" x="%s" y="%s" width="%s" height="%s" opacity="%s" ' +
    'preserveAspectRatio="none" transform="rotate(%s %s %s)"/>',
    [Esc(href), Esc(href), N(x), N(y), N(w), N(h), N(opacity), N(angle), N(x + w / 2), N(y + h / 2)]));
end;

procedure PolyPoints(const P: array of TPt; filled: Boolean);
var
  i: Integer;
  pts: string;
begin
  pts := '';
  for i := 0 to High(P) do
    pts := pts + N(P[i].x) + ',' + N(P[i].y) + ' ';
  if filled then
    Emit(Format('<polygon points="%s" fill="%s"/>', [Trim(pts), CurHex]))
  else
    Emit(Format('<polyline points="%s" %s/>', [Trim(pts), StrokeAttr(1)]));
end;

procedure SetTheme(i: Integer);
begin
  ThemeIdx := EnsureRange(i, 0, High(THEMES));
end;

function FindTheme(const name: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(THEMES) do
    if SameText(THEMES[i].name, name) then Exit(i);
end;

procedure Col(r, g, b: Byte);
var
  t: Single;
  th: TTheme;
begin
  th := THEMES[ThemeIdx];
  if (r = 220) and (g = 90) and (b = 20) then
  begin
    ColRaw(th.accent.r, th.accent.g, th.accent.b);
    Exit;
  end;
  if MaxValue([Integer(r), g, b]) - MinValue([Integer(r), g, b]) <= 24 then
  begin
    { สีเทา: 22 = ink, 252 = paper, ระหว่างนั้นไล่สี }
    t := EnsureRange(((r + g + b) / 3 - 22) / 230, 0, 1);
    ColRaw(Round(th.ink.r + (th.paper.r - th.ink.r) * t),
           Round(th.ink.g + (th.paper.g - th.ink.g) * t),
           Round(th.ink.b + (th.paper.b - th.ink.b) * t));
    Exit;
  end;
  ColRaw(r, g, b);
end;

procedure ColDoc(const c, def: TRgb);
begin
  if (c.r = def.r) and (c.g = def.g) and (c.b = def.b) then
    Col(c.r, c.g, c.b)
  else
    ColRaw(c.r, c.g, c.b);
end;

function Pt(x, y: Single): TPt;
begin
  Result.x := x;
  Result.y := y;
end;

procedure FillRect(x, y, w, h: Single);
var
  rc: TSDL_FRect;
begin
  if SvgOn then
  begin
    Emit(Format('<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>', [N(x), N(y), N(w), N(h), CurHex]));
    Exit;
  end;
  rc.x := x; rc.y := y; rc.w := w; rc.h := h;
  SDL_RenderFillRect(Ren, @rc);
end;

procedure StrokeRect(x, y, w, h: Single);
var
  rc: TSDL_FRect;
begin
  if SvgOn then
  begin
    Emit(Format('<rect x="%s" y="%s" width="%s" height="%s" %s/>', [N(x + 0.5), N(y + 0.5), N(w - 1), N(h - 1), StrokeAttr(1)]));
    Exit;
  end;
  rc.x := x; rc.y := y; rc.w := w; rc.h := h;
  SDL_RenderRect(Ren, @rc);
end;

procedure ColRaw(r, g, b: Byte);
begin
  CurHex := Format('#%.2x%.2x%.2x', [r, g, b]);
  CurCol.r := r / 255;
  CurCol.g := g / 255;
  CurCol.b := b / 255;
  CurCol.a := 1;
  if not SvgOn then
    SDL_SetRenderDrawColor(Ren, r, g, b, 255);
end;

procedure Ink;   begin Col(22, 22, 22); end;
procedure Paper; begin Col(252, 252, 250); end;

procedure AddV(x, y: Single);
begin
  if VertN >= Length(Verts) then
    SetLength(Verts, VertN * 2 + 256);
  Verts[VertN].position.x := x;
  Verts[VertN].position.y := y;
  Verts[VertN].color := CurCol;
  Verts[VertN].tex_coord.x := 0;
  Verts[VertN].tex_coord.y := 0;
  Inc(VertN);
end;

procedure Tri(x1, y1, x2, y2, x3, y3: Single);
begin
  if SvgOn then
  begin
    PolyPoints([Pt(x1, y1), Pt(x2, y2), Pt(x3, y3)], True);
    Exit;
  end;
  AddV(x1, y1); AddV(x2, y2); AddV(x3, y3);
end;

procedure Quad(const a, b, c, d: TPt);   // a-b ขอบหนึ่ง, d-c อีกขอบ
begin
  if SvgOn then
  begin
    PolyPoints([a, b, c, d], True);
    Exit;
  end;
  Tri(a.x, a.y, b.x, b.y, c.x, c.y);
  Tri(a.x, a.y, c.x, c.y, d.x, d.y);
end;

procedure Flush;
begin
  if (VertN > 0) and not SvgOn then
    SDL_RenderGeometry(Ren, nil, @Verts[0], VertN, nil, 0);
  VertN := 0;
end;

procedure Txt(x, y: Single; const s: string);
begin
  if SvgOn then
  begin
    if Trim(s) <> '' then
      Emit(Format('<text x="%s" y="%s" fill="%s" font-family="Consolas, Menlo, monospace" font-size="9.5" ' +
        'textLength="%s" lengthAdjust="spacingAndGlyphs" xml:space="preserve">%s</text>',
        [N(x), N(y + 7.5), CurHex, N(Length(s) * 8), Esc(s)]));
    Exit;
  end;
  SDL_RenderDebugText(Ren, x, y, PAnsiChar(s));
end;

procedure Line(x1, y1, x2, y2: Single);
begin
  if SvgOn then
  begin
    Emit(Format('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="1" stroke-linecap="round"/>',
      [N(x1), N(y1), N(x2), N(y2), CurHex]));
    Exit;
  end;
  SDL_RenderLine(Ren, x1, y1, x2, y2);
end;

procedure ThickLine(x1, y1, x2, y2, w: Single);
var
  dx, dy, L: Single;
begin
  if SvgOn then
  begin
    Emit(Format('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="%s"/>',
      [N(x1), N(y1), N(x2), N(y2), CurHex, N(w)]));
    Exit;
  end;
  dx := x2 - x1; dy := y2 - y1;
  L := Hypot(dx, dy);
  if L < 1e-4 then Exit;
  dx := -dy / L * w / 2;
  dy := (x2 - x1) / L * w / 2;
  Quad(Pt(x1 + dx, y1 + dy), Pt(x2 + dx, y2 + dy), Pt(x2 - dx, y2 - dy), Pt(x1 - dx, y1 - dy));
  Flush;
end;

procedure Disc(cx, cy, r: Single);
var
  k, n_: Integer;
  a0, a1: Single;
begin
  if SvgOn then
  begin
    Emit(Format('<circle cx="%s" cy="%s" r="%s" fill="%s"/>', [N(cx), N(cy), N(r), CurHex]));
    Exit;
  end;
  n_ := Max(10, Round(r * 3));
  for k := 0 to n_ - 1 do
  begin
    a0 := 2 * Pi * k / n_;
    a1 := 2 * Pi * (k + 1) / n_;
    Tri(cx, cy, cx + r * Cos(a0), cy + r * Sin(a0), cx + r * Cos(a1), cy + r * Sin(a1));
  end;
  Flush;
end;

{ แถบโค้งหนาระหว่างรัศมี r1..r2 จากมุม a0 ถึง a1 }
procedure ArcBand(cx, cy, r1, r2, a0, a1: Single);
var
  k, n_: Integer;
  b0, b1: Single;
  P: array of TPt;
begin
  n_ := Max(2, Ceil(Abs(a1 - a0) * r2 / 2.5));
  if SvgOn then
  begin
    { แถบโค้งเป็นรูปเดียว: ขอบนอกไป แล้วขอบในกลับ }
    SetLength(P, 2 * (n_ + 1));
    for k := 0 to n_ do
    begin
      b0 := a0 + (a1 - a0) * k / n_;
      P[k] := Pt(cx + r2 * Cos(b0), cy + r2 * Sin(b0));
      P[2 * n_ + 1 - k] := Pt(cx + r1 * Cos(b0), cy + r1 * Sin(b0));
    end;
    PolyPoints(P, True);
    Exit;
  end;
  for k := 0 to n_ - 1 do
  begin
    b0 := a0 + (a1 - a0) * k / n_;
    b1 := a0 + (a1 - a0) * (k + 1) / n_;
    Quad(Pt(cx + r1 * Cos(b0), cy + r1 * Sin(b0)), Pt(cx + r1 * Cos(b1), cy + r1 * Sin(b1)),
         Pt(cx + r2 * Cos(b1), cy + r2 * Sin(b1)), Pt(cx + r2 * Cos(b0), cy + r2 * Sin(b0)));
  end;
  Flush;
end;

procedure ArcLine(cx, cy, r, a0, a1: Single);
var
  k, n_: Integer;
  b0, b1: Single;
  P: array of TPt;
begin
  n_ := Max(2, Ceil(Abs(a1 - a0) * r / 3));
  if SvgOn then
  begin
    SetLength(P, n_ + 1);
    for k := 0 to n_ do
    begin
      b0 := a0 + (a1 - a0) * k / n_;
      P[k] := Pt(cx + r * Cos(b0), cy + r * Sin(b0));
    end;
    PolyPoints(P, False);
    Exit;
  end;
  for k := 0 to n_ - 1 do
  begin
    b0 := a0 + (a1 - a0) * k / n_;
    b1 := a0 + (a1 - a0) * (k + 1) / n_;
    Line(cx + r * Cos(b0), cy + r * Sin(b0), cx + r * Cos(b1), cy + r * Sin(b1));
  end;
end;

procedure RoundRectPts(x, y, w, h, rad: Single; out P: TPtArr);
const
  SEG = 5;
var
  k, c, n_: Integer;
  cx, cy, a: Single;
begin
  SetLength(P, 4 * (SEG + 1));
  n_ := 0;
  for c := 0 to 3 do
  begin
    case c of
      0: begin cx := x + w - rad; cy := y + rad; end;
      1: begin cx := x + w - rad; cy := y + h - rad; end;
      2: begin cx := x + rad;     cy := y + h - rad; end;
    else begin cx := x + rad;     cy := y + rad; end;
    end;
    for k := 0 to SEG do
    begin
      a := -Pi / 2 + (c + k / SEG) * Pi / 2;
      P[n_] := Pt(cx + rad * Cos(a), cy + rad * Sin(a));
      Inc(n_);
    end;
  end;
end;

procedure FillRoundRect(x, y, w, h, rad: Single);
var
  P: TPtArr;
  i, j: Integer;
begin
  if SvgOn then
  begin
    Emit(Format('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s"/>',
      [N(x), N(y), N(w), N(h), N(rad), CurHex]));
    Exit;
  end;
  RoundRectPts(x, y, w, h, rad, P);
  for i := 0 to High(P) do
  begin
    j := (i + 1) mod Length(P);
    Tri(x + w / 2, y + h / 2, P[i].x, P[i].y, P[j].x, P[j].y);
  end;
  Flush;
end;

procedure StrokeRoundRect(x, y, w, h, rad: Single);
var
  P: TPtArr;
  i, j: Integer;
begin
  if SvgOn then
  begin
    Emit(Format('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" %s/>',
      [N(x), N(y), N(w), N(h), N(rad), StrokeAttr(1)]));
    Exit;
  end;
  RoundRectPts(x, y, w, h, rad, P);
  for i := 0 to High(P) do
  begin
    j := (i + 1) mod Length(P);
    Line(P[i].x, P[i].y, P[j].x, P[j].y);
  end;
end;

{ ป้ายแบบ pill: ทึบ = พื้นดำตัวขาว, โปร่ง = กรอบดำ; คืนค่าความกว้าง }
function Pill(x, y: Single; const s: string; filled: Boolean): Single;
begin
  Result := Length(s) * 8 + 12;
  Ink;
  if filled then
  begin
    FillRoundRect(x, y, Result, 15, 6);
    Paper;
  end
  else
  begin
    Paper;
    FillRoundRect(x, y, Result, 15, 6);
    Ink;
    StrokeRoundRect(x, y, Result, 15, 6);
  end;
  Txt(x + 6, y + 4, s);
end;

procedure DashedCircle(cx, cy, r: Single);
var
  k, segs: Integer;
begin
  segs := Max(16, Round(r * 2 * Pi / 7));
  if Odd(segs) then Inc(segs);
  if SvgOn then
  begin
    Emit(Format('<circle cx="%s" cy="%s" r="%s" %s stroke-dasharray="%s %s"/>',
      [N(cx), N(cy), N(r), StrokeAttr(1), N(2 * Pi * r / segs), N(2 * Pi * r / segs)]));
    Exit;
  end;
  for k := 0 to segs - 1 do
    if not Odd(k) then
      ArcLine(cx, cy, r, 2 * Pi * k / segs, 2 * Pi * (k + 1) / segs);
end;

procedure DashedLine(x1, y1, x2, y2: Single);
var
  L, t0, t1: Single;
  k, n_: Integer;
begin
  if SvgOn then
  begin
    Emit(Format('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="1" stroke-dasharray="4 4"/>',
      [N(x1), N(y1), N(x2), N(y2), CurHex]));
    Exit;
  end;
  L := Hypot(x2 - x1, y2 - y1);
  n_ := Max(1, Round(L / 4));
  for k := 0 to n_ - 1 do
    if not Odd(k) then
    begin
      t0 := k / n_; t1 := (k + 1) / n_;
      Line(x1 + (x2 - x1) * t0, y1 + (y2 - y1) * t0, x1 + (x2 - x1) * t1, y1 + (y2 - y1) * t1);
    end;
end;

procedure DotLine(x1, y1, x2, y2: Single);
var
  L, t: Single;
  k, n_: Integer;
begin
  if SvgOn then
  begin
    Emit(Format('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="1" stroke-dasharray="1 3"/>',
      [N(x1), N(y1), N(x2), N(y2), CurHex]));
    Exit;
  end;
  L := Hypot(x2 - x1, y2 - y1);
  n_ := Max(1, Floor(L / 4));
  for k := 0 to n_ do
  begin
    t := k / n_;
    SDL_RenderPoint(Ren, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
  end;
end;

procedure Panel(x, y, w, h: Single);
begin
  Paper;
  FillRoundRect(x, y, w, h, 7);
  Col(70, 70, 70);
  StrokeRoundRect(x, y, w, h, 7);
end;

procedure SetClip(x, y, w, h: Integer);
var
  rc: TSDL_Rect;
begin
  if SvgOn then Exit;
  rc.x := x; rc.y := y; rc.w := w; rc.h := h;
  SDL_SetRenderClipRect(Ren, @rc);
end;

procedure ClearClip;
begin
  if SvgOn then Exit;
  SDL_SetRenderClipRect(Ren, nil);
end;

end.

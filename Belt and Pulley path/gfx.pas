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

var
  Ren: PSDL_Renderer;

function Pt(x, y: Single): TPt;
procedure Col(r, g, b: Byte);
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

implementation

uses
  Math;

var
  Verts: array of TSDL_Vertex;
  VertN: Integer = 0;
  CurCol: TSDL_FColor;

function Pt(x, y: Single): TPt;
begin
  Result.x := x;
  Result.y := y;
end;

procedure FillRect(x, y, w, h: Single);
var
  rc: TSDL_FRect;
begin
  rc.x := x; rc.y := y; rc.w := w; rc.h := h;
  SDL_RenderFillRect(Ren, @rc);
end;

procedure StrokeRect(x, y, w, h: Single);
var
  rc: TSDL_FRect;
begin
  rc.x := x; rc.y := y; rc.w := w; rc.h := h;
  SDL_RenderRect(Ren, @rc);
end;

procedure Col(r, g, b: Byte);
begin
  SDL_SetRenderDrawColor(Ren, r, g, b, 255);
  CurCol.r := r / 255;
  CurCol.g := g / 255;
  CurCol.b := b / 255;
  CurCol.a := 1;
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
  AddV(x1, y1); AddV(x2, y2); AddV(x3, y3);
end;

procedure Quad(const a, b, c, d: TPt);   // a-b ขอบหนึ่ง, d-c อีกขอบ
begin
  Tri(a.x, a.y, b.x, b.y, c.x, c.y);
  Tri(a.x, a.y, c.x, c.y, d.x, d.y);
end;

procedure Flush;
begin
  if VertN > 0 then
    SDL_RenderGeometry(Ren, nil, @Verts[0], VertN, nil, 0);
  VertN := 0;
end;

procedure Txt(x, y: Single; const s: string);
begin
  SDL_RenderDebugText(Ren, x, y, PAnsiChar(s));
end;

procedure Line(x1, y1, x2, y2: Single);
begin
  SDL_RenderLine(Ren, x1, y1, x2, y2);
end;

procedure ThickLine(x1, y1, x2, y2, w: Single);
var
  dx, dy, L: Single;
begin
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
  k, n: Integer;
  a0, a1: Single;
begin
  n := Max(10, Round(r * 3));
  for k := 0 to n - 1 do
  begin
    a0 := 2 * Pi * k / n;
    a1 := 2 * Pi * (k + 1) / n;
    Tri(cx, cy, cx + r * Cos(a0), cy + r * Sin(a0), cx + r * Cos(a1), cy + r * Sin(a1));
  end;
  Flush;
end;

{ แถบโค้งหนาระหว่างรัศมี r1..r2 จากมุม a0 ถึง a1 }
procedure ArcBand(cx, cy, r1, r2, a0, a1: Single);
var
  k, n: Integer;
  b0, b1: Single;
begin
  n := Max(2, Ceil(Abs(a1 - a0) * r2 / 2.5));
  for k := 0 to n - 1 do
  begin
    b0 := a0 + (a1 - a0) * k / n;
    b1 := a0 + (a1 - a0) * (k + 1) / n;
    Quad(Pt(cx + r1 * Cos(b0), cy + r1 * Sin(b0)), Pt(cx + r1 * Cos(b1), cy + r1 * Sin(b1)),
         Pt(cx + r2 * Cos(b1), cy + r2 * Sin(b1)), Pt(cx + r2 * Cos(b0), cy + r2 * Sin(b0)));
  end;
  Flush;
end;

procedure ArcLine(cx, cy, r, a0, a1: Single);
var
  k, n: Integer;
  b0, b1: Single;
begin
  n := Max(2, Ceil(Abs(a1 - a0) * r / 3));
  for k := 0 to n - 1 do
  begin
    b0 := a0 + (a1 - a0) * k / n;
    b1 := a0 + (a1 - a0) * (k + 1) / n;
    Line(cx + r * Cos(b0), cy + r * Sin(b0), cx + r * Cos(b1), cy + r * Sin(b1));
  end;
end;

procedure RoundRectPts(x, y, w, h, rad: Single; out P: TPtArr);
const
  SEG = 5;
var
  k, c, n: Integer;
  cx, cy, a: Single;
begin
  SetLength(P, 4 * (SEG + 1));
  n := 0;
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
      P[n] := Pt(cx + rad * Cos(a), cy + rad * Sin(a));
      Inc(n);
    end;
  end;
end;

procedure FillRoundRect(x, y, w, h, rad: Single);
var
  P: TPtArr;
  i, j: Integer;
begin
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
  for k := 0 to segs - 1 do
    if not Odd(k) then
      ArcLine(cx, cy, r, 2 * Pi * k / segs, 2 * Pi * (k + 1) / segs);
end;

procedure DashedLine(x1, y1, x2, y2: Single);
var
  L, t0, t1: Single;
  k, n: Integer;
begin
  L := Hypot(x2 - x1, y2 - y1);
  n := Max(1, Round(L / 4));
  for k := 0 to n - 1 do
    if not Odd(k) then
    begin
      t0 := k / n; t1 := (k + 1) / n;
      Line(x1 + (x2 - x1) * t0, y1 + (y2 - y1) * t0, x1 + (x2 - x1) * t1, y1 + (y2 - y1) * t1);
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
  rc.x := x; rc.y := y; rc.w := w; rc.h := h;
  SDL_SetRenderClipRect(Ren, @rc);
end;

end.

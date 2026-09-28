unit TestPoisonFrees;
{$MODE delphi}
{$EXCESSPRECISION OFF}
interface
procedure RunPoisonFreesTests;
implementation
uses
  SysUtils,
  PoisonFrees,
  TestSupport;

type
  TFreedProbe = class
    Value: Integer;
    Name: AnsiString;
  end;

{$IFOPT C+}
function AllPoison(P: Pointer; Size: PtrUInt): Boolean;
var
  I: PtrUInt;
begin
  for I := 0 to Size - 1 do
    if PByte(P)[I] <> PoisonByte then
      Exit(False);
  Result := True;
end;

// Reading freed memory is safe here only because the block is still in the quarantine.
procedure RunPattern;
var
  P: Pointer;
  Size: PtrUInt;
  Probe: TFreedProbe;
  Pattern: PtrUInt;
begin
  FillChar(Pattern, SizeOf(Pattern), PoisonByte);
  GetMem(P, 100);
  FillChar(P^, 100, 1);
  Size := MemSize(P);
  FreeMem(P);
  Check(AllPoison(P, Size), 'a freed block reads as the pattern');
  Probe := TFreedProbe.Create;
  Probe.Name := 'probe';
  P := Probe;
  Probe.Free;
  Check(PPtrUInt(P)^ = Pattern, 'a freed object''s VMT slot is the pattern');
  Check(IsPoisonAddress(PPtrUInt(P)^), 'the pattern is a poisoned address');
  Check(IsPoisonAddress(PPtrUInt(P)^ + 16), 'a field behind the pattern is poisoned');
  Check(not IsPoisonAddress(PtrUInt(P)), 'a heap address is not poisoned');
end;

procedure RunNoReuse;
var
  Freed: Pointer;
  Blocks: array[0..255] of Pointer;
  I: Integer;
  Reused: Boolean;
begin
  GetMem(Freed, 48);
  FreeMem(Freed);
  Reused := False;
  for I := 0 to High(Blocks) do
  begin
    GetMem(Blocks[I], 48);
    Reused := Reused or (Blocks[I] = Freed);
  end;
  Check(not Reused, 'a quarantined address is not handed out again');
  for I := 0 to High(Blocks) do
    FreeMem(Blocks[I]);
end;

procedure RunReallocate;
var
  P, Old: Pointer;
  Size: PtrUInt;
begin
  GetMem(P, 32);
  FillChar(P^, 32, 7);
  Old := P;
  Size := MemSize(P);
  ReallocMem(P, 4096);
  Check(P <> Old, 'a grown block moves');
  Check(PByte(P)[31] = 7, 'a moved block keeps its contents');
  Check(AllPoison(Old, Size), 'the block a reallocation left is poisoned');
  FreeMem(P);
end;

procedure RunBudget;
var
  First: Pointer;
  I: Integer;
  P: Pointer;
  Stats: TPoisonFreesStats;
begin
  FlushPoisonQuarantine;
  GetMem(First, 1000);
  FreeMem(First);
  for I := 1 to 200 do
  begin
    GetMem(P, 1000);
    FreeMem(P);
  end;
  Stats := PoisonFreesStats;
  Check(Stats.QuarantinedBytes <= 64 * 1024, 'the quarantine stays within its budget');
  Check(Stats.ReleasedBlocks > 0, 'the oldest blocks leave the quarantine');
end;

procedure RunWriteAfterFree;
var
  P: Pointer;
  Stats: TPoisonFreesStats;
begin
  FlushPoisonQuarantine;
  GetMem(P, 64);
  FreeMem(P);
  PByte(P)[10] := 0;
  FlushPoisonQuarantine;
  Stats := PoisonFreesStats;
  CheckInt(1, Stats.WritesAfterFree, 'a write to freed memory is found');
  Check(Stats.FirstWriteAfterFree = P, 'the written block is named');
  CheckInt(10, Stats.FirstWriteOffset, 'the written offset is named');
end;

procedure RunDoubleFree;
var
  P: Pointer;
  Raised: Boolean;
begin
  GetMem(P, 64);
  FreeMem(P);
  Raised := False;
  try
    FreeMem(P);
  except
    on EInvalidPointer do
      Raised := True;
  end;
  Check(Raised, 'a block freed twice raises');
end;

procedure RunInstalled;
begin
  RunPattern;
  RunNoReuse;
  RunReallocate;
  RunBudget;
  RunWriteAfterFree;
  RunDoubleFree;
end;
{$ENDIF}

procedure RunPoisonFreesTests;
var
  Before: Pointer;
begin
  {$IFOPT C+}
  Check(PoisonFreesAvailable, 'debug builds have poisoned frees');
  // A block from before the install is the wrapped manager's; the wrapper frees it too.
  GetMem(Before, 64);
  InstallPoisonFrees(64 * 1024);
  try
    Check(PoisonFreesInstalled, 'the wrapper is installed');
    FreeMem(Before);
    Check(AllPoison(Before, 64), 'a block from before the install is poisoned');
    RunInstalled;
  finally
    UninstallPoisonFrees;
  end;
  Check(not PoisonFreesInstalled, 'the wrapper is removed');
  {$ELSE}
  Check(not PoisonFreesAvailable, 'release builds have no poisoned frees');
  {$ENDIF}
end;

end.

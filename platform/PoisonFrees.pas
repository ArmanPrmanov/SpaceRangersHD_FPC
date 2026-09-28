unit PoisonFrees;
{$MODE delphi}
{$EXCESSPRECISION OFF}
// Address arithmetic wraps on purpose.
{$Q-}
{$R-}

// CHANGE: ENHANCEMENT - Poisoned frees (ROADMAP.md, Phase 5; docs/network.md, "Applying state
// (the safe point)"). With --poison-frees a debug build wraps the memory manager: a freed block
// is filled with PoisonByte and held in a FIFO quarantine, bounded by bytes, before it is really
// freed. A stale reference to a freed object then reads $DEDEDEDEDEDEDEDE as its VMT or as a
// pointer field and faults at once, instead of reading whatever the next allocation at the same
// address put there (bug ef2e7da, docs/progress/2026-09-26-phase4.md).
//
// The wrapper adds no header: every block is the wrapped manager's, whether it was allocated
// before or after the install, and its size is the wrapped manager's MemSize. One lock guards the
// quarantine, since the UI, turn and network threads all free. Release builds compile the wrapper
// out and refuse the option.
interface

const
  PoisonByte = $DE;
  DefaultPoisonQuarantineMB = 128;

type
  TPoisonFreesStats = record
    QuarantinedBlocks: PtrUInt;
    QuarantinedBytes: PtrUInt;
    // Blocks handed back to the wrapped manager.
    ReleasedBlocks: Int64;
    // Blocks found changed when they left the quarantine: something wrote to freed memory.
    WritesAfterFree: Int64;
    FirstWriteAfterFree: Pointer;
    FirstWriteOffset: PtrUInt;
  end;

// True in debug builds, which compile the wrapper in.
function PoisonFreesAvailable: Boolean;
// Wraps the current memory manager, holding back up to QuarantineBytes of freed blocks.
procedure InstallPoisonFrees(QuarantineBytes: PtrUInt);
// Restores the wrapped manager and frees the quarantine (for the unit tests).
procedure UninstallPoisonFrees;
function PoisonFreesInstalled: Boolean;
// Hands every quarantined block back, checking that none was written to.
procedure FlushPoisonQuarantine;
function PoisonFreesStats: TPoisonFreesStats;
function PoisonFreesSummary: AnsiString;
// A log line for an exception while the wrapper is installed: whether an access violation
// touched a poisoned address. Empty when there is nothing to say.
function PoisonFaultHint(E: TObject): AnsiString;
// A freed block's pattern, or an x64 Windows report of a fault on such a non-canonical address.
function IsPoisonAddress(Address: PtrUInt): Boolean;

implementation

uses
  SysUtils;

function IsPoisonAddress(Address: PtrUInt): Boolean;
var
  Pattern: PtrUInt;
begin
  FillChar(Pattern, SizeOf(Pattern), PoisonByte);
  // A field of a freed object: the pattern plus a small offset. Windows reports a general
  // protection fault, which a non-canonical x64 address raises, at address -1.
  Result := (Address - Pattern < $10000) or (Address = High(PtrUInt));
end;

{$IFOPT C+}
type
  TPointerRing = array[0..High(PtrInt) div SizeOf(Pointer) - 1] of Pointer;
  PPointerRing = ^TPointerRing;

var
  Wrapped: TMemoryManager;
  Lock: TRTLCriticalSection;
  LockReady: Boolean;
  Active: Boolean;
  // A ring of the quarantined blocks, oldest at Head; bounded by Budget bytes and Capacity blocks.
  Ring: PPointerRing;
  Capacity, Head, Count: PtrUInt;
  Budget, Bytes: PtrUInt;
  Stats: TPoisonFreesStats;

// Whether the block is all PoisonByte; Offset is the first byte that is not.
function IsPoisoned(P: Pointer; Size: PtrUInt; out Offset: PtrUInt): Boolean;
var
  Pattern: PtrUInt;
  Words: PPtrUInt;
  Bytes: PByte;
  I: PtrUInt;
begin
  FillChar(Pattern, SizeOf(Pattern), PoisonByte);
  Words := P;
  I := 0;
  while (I < Size div SizeOf(PtrUInt)) and (Words[I] = Pattern) do
    Inc(I);
  Bytes := P;
  Offset := I * SizeOf(PtrUInt);
  while (Offset < Size) and (Bytes[Offset] = PoisonByte) do
    Inc(Offset);
  Result := Offset >= Size;
end;

function InQuarantine(P: Pointer): Boolean;
var
  I: PtrUInt;
begin
  for I := 0 to Count - 1 do
    if Ring[(Head + I) mod Capacity] = P then
      Exit(True);
  Result := False;
end;

// With the lock held.
procedure ReleaseOldest;
var
  P: Pointer;
  Size, Offset: PtrUInt;
begin
  P := Ring[Head];
  Head := (Head + 1) mod Capacity;
  Dec(Count);
  Size := Wrapped.MemSize(P);
  Dec(Bytes, Size);
  if not IsPoisoned(P, Size, Offset) then
  begin
    if Stats.WritesAfterFree = 0 then
    begin
      Stats.FirstWriteAfterFree := P;
      Stats.FirstWriteOffset := Offset;
    end;
    Inc(Stats.WritesAfterFree);
  end;
  Wrapped.Freemem(P);
  Inc(Stats.ReleasedBlocks);
end;

function PoisonFreemem(P: Pointer): PtrUInt;
var
  Size, Offset: PtrUInt;
  Suspect, DoubleFree: Boolean;
begin
  if P = nil then
    Exit(0);
  if not Active then
    Exit(Wrapped.Freemem(P));
  Size := Wrapped.MemSize(P);
  Result := Size;
  // Freed memory is all pattern; the quarantine confirms a double free, since live data may
  // match. The block is still the caller's, so it is filled before taking the lock.
  Suspect := IsPoisoned(P, Size, Offset);
  if not Suspect then
    FillChar(P^, Size, PoisonByte);
  DoubleFree := False;
  EnterCriticalSection(Lock);
  try
    if not Active then
      Exit(Wrapped.Freemem(P));
    DoubleFree := Suspect and InQuarantine(P);
    if not DoubleFree then
    begin
      if Size > Budget div 4 then
      begin
        // A block this large would empty the quarantine; poison it and let it go.
        Wrapped.Freemem(P);
        Inc(Stats.ReleasedBlocks);
      end
      else
      begin
        while (Count > 0) and ((Count = Capacity) or (Bytes + Size > Budget)) do
          ReleaseOldest;
        Ring[(Head + Count) mod Capacity] := P;
        Inc(Count);
        Inc(Bytes, Size);
      end;
    end;
  finally
    LeaveCriticalSection(Lock);
  end;
  // Raised outside the lock: the exception object is allocated.
  if DoubleFree then
    raise EInvalidPointer.Create(
        'Invalid pointer operation: $' + IntToHex(PtrUInt(P), SizeOf(Pointer) * 2)
            + ' was freed twice'
    );
end;

function PoisonFreememSize(P: Pointer; Size: PtrUInt): PtrUInt;
begin
  Result := PoisonFreemem(P);
end;

// A block that shrinks by at most half stays and has its tail poisoned; any other resize moves
// and poisons the old block, so a stale pointer into a reallocated buffer faults too. The
// wrapped ReAllocMem is never called, since it may move a block without poisoning it.
function PoisonReAllocMem(var P: Pointer; Size: PtrUInt): Pointer;
var
  OldSize: PtrUInt;
  Moved: Pointer;
begin
  if not Active then
    Exit(Wrapped.ReAllocMem(P, Size));
  if Size = 0 then
  begin
    PoisonFreemem(P);
    P := nil;
  end
  else if P = nil then
    P := Wrapped.Getmem(Size)
  else
  begin
    OldSize := Wrapped.MemSize(P);
    if (Size <= OldSize) and (Size > OldSize div 2) then
      FillChar(PByte(P)[Size], OldSize - Size, PoisonByte)
    else
    begin
      Moved := Wrapped.Getmem(Size);
      if OldSize < Size then
        Move(P^, Moved^, OldSize)
      else
        Move(P^, Moved^, Size);
      PoisonFreemem(P);
      P := Moved;
    end;
  end;
  Result := P;
end;

function PoisonFreesAvailable: Boolean;
begin
  Result := True;
end;

procedure InstallPoisonFrees(QuarantineBytes: PtrUInt);
var
  Wrapper: TMemoryManager;
begin
  if Active then
    Exit;
  if not LockReady then
  begin
    InitCriticalSection(Lock);
    LockReady := True;
  end;
  GetMemoryManager(Wrapped);
  Budget := QuarantineBytes;
  // Room for blocks of 32 bytes on average; the budget in bytes usually binds first.
  Capacity := QuarantineBytes div 32;
  if Capacity < 1024 then
    Capacity := 1024;
  Ring := Wrapped.Getmem(Capacity * SizeOf(Pointer));
  Head := 0;
  Count := 0;
  Bytes := 0;
  FillChar(Stats, SizeOf(Stats), 0);
  Wrapper := Wrapped;
  Wrapper.Freemem := PoisonFreemem;
  Wrapper.FreememSize := PoisonFreememSize;
  Wrapper.ReAllocMem := PoisonReAllocMem;
  Active := True;
  SetMemoryManager(Wrapper);
end;

procedure UninstallPoisonFrees;
begin
  if not Active then
    Exit;
  EnterCriticalSection(Lock);
  try
    // A free that already reached the wrapper and waits for the lock passes straight through.
    Active := False;
    SetMemoryManager(Wrapped);
    while Count > 0 do
      ReleaseOldest;
    Wrapped.Freemem(Ring);
    Ring := nil;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function PoisonFreesInstalled: Boolean;
begin
  Result := Active;
end;

procedure FlushPoisonQuarantine;
begin
  if not Active then
    Exit;
  EnterCriticalSection(Lock);
  try
    while Count > 0 do
      ReleaseOldest;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function PoisonFreesStats: TPoisonFreesStats;
begin
  if not LockReady then
  begin
    FillChar(Result, SizeOf(Result), 0);
    Exit;
  end;
  EnterCriticalSection(Lock);
  try
    Result := Stats;
    Result.QuarantinedBlocks := Count;
    Result.QuarantinedBytes := Bytes;
  finally
    LeaveCriticalSection(Lock);
  end;
end;
{$ELSE}
// Release builds: no wrapper; GameBootstrap refuses --poison-frees.
function PoisonFreesAvailable: Boolean;
begin
  Result := False;
end;

procedure InstallPoisonFrees(QuarantineBytes: PtrUInt);
begin
  raise Exception.Create('--poison-frees needs a debug build');
end;

procedure UninstallPoisonFrees;
begin
end;

function PoisonFreesInstalled: Boolean;
begin
  Result := False;
end;

procedure FlushPoisonQuarantine;
begin
end;

function PoisonFreesStats: TPoisonFreesStats;
begin
  FillChar(Result, SizeOf(Result), 0);
end;
{$ENDIF}

function PoisonFreesSummary: AnsiString;
var
  Current: TPoisonFreesStats;
begin
  Current := PoisonFreesStats;
  Result := Format(
      'Poisoned frees: %d blocks (%d KB) in quarantine, %d released, %d written after free',
      [Current.QuarantinedBlocks, Current.QuarantinedBytes div 1024, Current.ReleasedBlocks,
          Current.WritesAfterFree]
  );
  if Current.WritesAfterFree > 0 then
    Result := Result + Format(
        ' (first at $%s, offset %d)',
        [IntToHex(PtrUInt(Current.FirstWriteAfterFree), SizeOf(Pointer) * 2),
            Current.FirstWriteOffset]
    );
end;

function PoisonFaultHint(E: TObject): AnsiString;
var
  Address: PtrUInt;
  Known: Boolean;
begin
  Result := '';
  if not PoisonFreesInstalled then
    Exit;
  if E is EInvalidPointer then
    Exit('Poisoned frees: an invalid pointer operation here may be a block freed twice');
  if not (E is EAccessViolation) then
    Exit;
  Known := False;
  Address := 0;
  {$IFDEF MSWINDOWS}
  if EAccessViolation(E).ExceptionRecord^.NumberParameters >= 2 then
  begin
    Address := PtrUInt(EAccessViolation(E).ExceptionRecord^.ExceptionInformation[1]);
    Known := True;
  end;
  {$ENDIF}
  if not Known then
    Result := 'Poisoned frees: freed memory reads as $DE bytes; an access violation through'
        + ' a pointer like $DEDEDEDEDEDEDEDE is a stale reference to a freed block'
  else if IsPoisonAddress(Address) then
    Result := 'Poisoned frees: the fault at $' + IntToHex(Address, SizeOf(Pointer) * 2)
        + ' is a poisoned address: a stale reference to a freed block'
  else
    Result := 'Poisoned frees: the fault at $' + IntToHex(Address, SizeOf(Pointer) * 2)
        + ' is not a poisoned address';
end;

finalization
  {$IFOPT C+}
  if LockReady and not Active then
    DoneCriticalSection(Lock);
  {$ENDIF}
end.

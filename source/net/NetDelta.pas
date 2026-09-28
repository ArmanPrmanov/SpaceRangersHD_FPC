{$EXCESSPRECISION OFF}
unit NetDelta;

// CHANGE: ENHANCEMENT - State compression for multiplayer (ROADMAP.md, Phase 5). A state
// travels either whole (compressed) or as a delta against a state the receiver already has:
// zstd with the old state as a reference prefix, as `zstd --patch-from` does. Deltas work on
// the uncompressed state, since compressed bytes change almost entirely even when little in
// the game changed, and zstd finds moved and resized runs, which a byte diff would not.
interface
uses
  EC_Buf;

// Appends the compressed Source to Target. Reference may be nil for a whole state.
procedure CompressState(Source, Reference, Target: TBufEC; Level: Integer = 3);
// Replaces Target with the state that Compressed holds; Reference must be the one it was
// compressed against (nil for a whole state). Raises on corrupt input.
procedure ExpandState(Compressed: Pointer; CompressedSize: Integer; Reference, Target: TBufEC);
implementation
uses
  SysUtils,
  NetNative,
  NetTransport;

function ReferenceData(Reference: TBufEC): Pointer;
begin
  if (Reference = nil) or (Reference.DataSize = 0) then
    Result := nil
  else
    Result := Reference.Data;
end;

function ReferenceSize(Reference: TBufEC): Int64;
begin
  if Reference = nil then
    Result := 0
  else
    Result := Reference.DataSize;
end;

procedure CompressState(Source, Reference, Target: TBufEC; Level: Integer);
var
  Capacity, Size: Int64;
  Start: Integer;
begin
  Capacity := sr_zstd_bound(Source.DataSize);
  Start := Target.DataSize;
  Target.SetPosition(Start);
  Target.EnsureWriteCapacity(Integer(Capacity));
  Size := sr_zstd_compress(
      @PByte(Target.Data)[Start],
      Capacity,
      Source.Data,
      Source.DataSize,
      ReferenceData(Reference),
      ReferenceSize(Reference),
      Level
  );
  if Size < 0 then
    raise Exception.Create('State compression failed: ' + NetworkErrorText);
  Target.SetSize(Start + Integer(Size));
  Target.SetPosition(Target.DataSize);
end;

procedure ExpandState(Compressed: Pointer; CompressedSize: Integer; Reference, Target: TBufEC);
var
  Declared, Size: Int64;
begin
  Declared := sr_zstd_content_size(Compressed, CompressedSize);
  if (Declared < 0) or (Declared > MaximumMessageSize) then
    raise Exception.Create('Corrupt state: no size');
  Target.Clear;
  Target.SetSize(Integer(Declared));
  Size := sr_zstd_decompress(
      Target.Data,
      Declared,
      Compressed,
      CompressedSize,
      ReferenceData(Reference),
      ReferenceSize(Reference)
  );
  if Size <> Declared then
    raise Exception.Create('Corrupt state: ' + NetworkErrorText);
  Target.SetPosition(0);
end;

end.

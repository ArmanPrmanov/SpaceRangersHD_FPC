unit TestCodecs;
{$MODE delphi}
{$EXCESSPRECISION OFF}
interface
procedure RunCodecTests(const WorkDirectory: string);
implementation
uses
  Classes,
  SysUtils,
  EC_BlockPar,
  EC_Buf,
  EC_Data,
  EC_HsFile,
  aPacket,
  ZLib,
  TestSupport;
const
  PackEntryDiskSize = 158;
  PackKindRaw = 1;
  PackKindChained = 2;
  PackKindFolder = 3;
  PackBlockSize = 65536;
  // Two compressed blocks; the second is partial.
  PackedFileSize = PackBlockSize + 4464;
var
  Work: string;

function WorkPath(const Name: string): string;
begin
  Result := IncludeTrailingPathDelimiter(Work) + Name;
end;

procedure SaveBuffer(Buf: TBufEC; const FileName: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    if Buf.DataSize > 0 then
      Stream.WriteBuffer(Buf.Data^, Buf.DataSize);
  finally
    Stream.Free;
  end;
end;

// Writes the envelope LoadFromEncryptedDatFile expects: CRC and keyed seed, then the
// ciphered payload, optionally behind the legacy size/CRC header.
procedure SaveEncryptedDat(
    Payload: TBufEC;
    SeedKey: Cardinal;
    SizeKey: Cardinal;
    Legacy: Boolean;
    const FileName: string
);
var
  Seed: Integer;
  Crc: Cardinal;
  Dat: TBufEC;
begin
  Seed := $2468ACE;
  Check(Payload.CompressZlibPayloadInPlace(False), 'DAT payload compresses');
  Crc := Payload.ComputeCrc32;
  Payload.ApplyDatXorCipher(Seed);
  Dat := TBufEC.Create;
  try
    if Legacy then
    begin
      Dat.AddDWord(Cardinal(Payload.DataSize + 8) xor SizeKey);
      Dat.AddDWord(0);
    end;
    Dat.AddDWord(Crc);
    Dat.AddDWord(Cardinal(Seed) xor SeedKey);
    Dat.AddBytes(Payload.Data, Payload.DataSize);
    SaveBuffer(Dat, FileName);
  finally
    Dat.Free;
  end;
end;

procedure AddBlockString(Buf: TBufEC; const Name: WideString; const Value: WideString);
begin
  Buf.AddByte(Ord(bpkString));
  Buf.AddWideStringZ(Name);
  Buf.AddWideStringZ(Value);
end;

procedure BuildBlockParPayload(Buf: TBufEC);
var
  i: Integer;
begin
  Buf.AddBoolean(False);
  Buf.AddInt32(3);
  AddBlockString(Buf, 'Name', 'Рейнджер');
  Buf.AddByte(Ord(bpkBlock));
  Buf.AddWideStringZ('Ship');
  Buf.AddBoolean(False);
  Buf.AddInt32(2);
  AddBlockString(Buf, 'Speed', '750');
  AddBlockString(Buf, 'Hull', 'Ranger');
  // Padding makes the payload large and repetitive enough to compress.
  Buf.AddByte(Ord(bpkString));
  Buf.AddWideStringZ('Filler');
  for i := 1 to 200 do
    Buf.AddWideChar('x');
  Buf.AddWord(0);
end;

procedure CheckBlockPar(Block: TBlockParEC; const Name: string);
begin
  CheckInt(3, Block.GetEntryCount, Name + ' entry count');
  CheckText('Рейнджер', Block.GetParam('Name'), Name + ' string param');
  CheckText('750', Block.GetBlock('Ship').GetParam('Speed'), Name + ' nested param');
  CheckText('Ranger', Block.GetParamByPath('Ship.Hull'), Name + ' param by path');
  CheckInt(200, Length(Block.GetParam('Filler')), Name + ' long param');
end;

procedure RunBlockParDatTests;
var
  Payload: TBufEC;
  Block: TBlockParEC;
  Legacy: Boolean;
  Name: string;
begin
  for Legacy := False to True do
  begin
    Name := 'BlockPar DAT' + BoolToStr(Legacy, ' legacy', '');
    Payload := TBufEC.Create;
    Block := TBlockParEC.Create;
    try
      BuildBlockParPayload(Payload);
      SaveEncryptedDat(
          Payload,
          BlockDatSeedKey,
          BlockDatCrcKey1 xor BlockDatCrcKey2,
          Legacy,
          WorkPath('block.dat')
      );
      Block.LoadFromEncryptedDatFile(WorkPath('block.dat'));
      CheckBlockPar(Block, Name);
    except
      on E: Exception do
        ReportException(Name, E);
    end;
    Block.Free;
    Payload.Free;
  end;
end;

procedure RunBlockParTextTests;
var
  Source, Parsed: TBlockParEC;
  First, Second: TBufEC;
  AnsiText: Boolean;
  Name: string;
begin
  for AnsiText := False to True do
  begin
    Name := 'BlockPar text' + BoolToStr(AnsiText, ' ANSI', ' UTF-16');
    Source := TBlockParEC.Create;
    Parsed := TBlockParEC.Create;
    First := TBufEC.Create;
    Second := TBufEC.Create;
    try
      Source.AddParam('Zeta', '1');
      Source.AddParam('Alpha', 'a=b');
      with Source.AddChildBlock('Child') do
      begin
        AddParam('Value', ' two words');
        AddChildBlock('Empty');
      end;
      Source.WriteTextBuffer(First, AnsiText, True);
      First.SetPosition(0);
      Parsed.LoadFromTextBufferWithEncodingProbe(First, False);
      Parsed.WriteTextBuffer(Second, AnsiText, True);
      Check(
          (First.DataSize = Second.DataSize)
              and CompareMem(First.Data, Second.Data, First.DataSize),
          Name + ' round trip bytes'
      );
      CheckText('a=b', Parsed.GetParam('Alpha'), Name + ' value with separator');
      CheckText(
          ' two words',
          Parsed.GetBlock('Child').GetParam('Value'),
          Name + ' keeps leading space'
      );
      CheckInt(2, Parsed.GetBlock('Child').GetEntryCount, Name + ' child entries');
    except
      on E: Exception do
        ReportException(Name, E);
    end;
    Second.Free;
    First.Free;
    Parsed.Free;
    Source.Free;
  end;
end;

procedure RunResourceDatTests;
var
  Payload, Content: TBufEC;
  Data: TDataEC;
  ContentFile: WideString;
begin
  ContentFile := WideString(WorkPath('content.bin'));
  Payload := TBufEC.Create;
  Content := TBufEC.Create;
  Data := TDataEC.Create;
  try
    Content.AddAnsiStringRaw('resource bytes');
    SaveBuffer(Content, WorkPath('content.bin'));
    // Entries must be in index order: FindEntry binary-searches the loaded array.
    Payload.AddInt32(3);
    Payload.AddByte(Ord(dekSubtree));
    Payload.AddWideStringZ('Bitmaps');
    Payload.AddInt32(1);
    Payload.AddByte(Ord(dekFile));
    Payload.AddWideStringZ('Logo');
    Payload.AddWideStringZ(ContentFile);
    Payload.AddByte(Ord(dekFile));
    Payload.AddWideStringZ('Readme');
    Payload.AddWideStringZ(ContentFile);
    Payload.AddByte(Ord(dekFile));
    Payload.AddWideStringZ('Readme2');
    Payload.AddWideStringZ(ContentFile);
    Payload.AddAnsiStringRaw(StringOfChar(#0, 256));
    SaveEncryptedDat(
        Payload,
        ResourceDatSeedKey,
        ResourceDatCrcKey1 xor ResourceDatCrcKey2,
        False,
        WorkPath('resource.dat')
    );
    Data.LoadFromEncryptedDatFile(WorkPath('resource.dat'));
    Check(Data.FileExistsByPath('Bitmaps.Logo'), 'Resource DAT nested entry');
    Check(Data.FileExistsByPath('Readme'), 'Resource DAT top entry');
    Check(not Data.FileExistsByPath('Bitmaps.Missing'), 'Resource DAT missing entry');
    Content.Clear;
    Data.ReadBufferByPath('Bitmaps/Logo', Content);
    CheckText('resource bytes', WideString(Content.ReadAnsiTextLine), 'Resource DAT read');
    // Siblings share one file object. A loaded subtree clears itself first, which
    // drops the link to its parent's list, so nested entries get their own.
    Check(
        Data.FindEntryByPath('Readme').SharedFileRef
            = Data.FindEntryByPath('Readme2').SharedFileRef,
        'Resource DAT interns file names'
    );
    Check(
        Data.FindEntryByPath('Bitmaps.Logo').SharedFileRef
            <> Data.FindEntryByPath('Readme').SharedFileRef,
        'Resource DAT subtree has its own file list'
    );
  except
    on E: Exception do
      ReportException('Resource DAT', E);
  end;
  Data.Free;
  Content.Free;
  Payload.Free;
end;

procedure AddPackEntry(
    Buf: TBufEC;
    const Name: AnsiString;
    Kind: Integer;
    DataSize: Cardinal;
    TargetOffset: Cardinal
);
var
  Entry: array[0..PackEntryDiskSize - 1] of Byte;
  Upper: AnsiString;
begin
  FillChar(Entry, SizeOf(Entry), 0);
  Upper := UpperCase(Name);
  PCardinal(@Entry[0])^ := DataSize;
  PCardinal(@Entry[4])^ := DataSize;
  Move(PAnsiChar(Upper)^, Entry[8], Length(Upper));
  Move(PAnsiChar(Name)^, Entry[71], Length(Name));
  PInteger(@Entry[134])^ := Kind;
  PInteger(@Entry[138])^ := Kind;
  PCardinal(@Entry[150])^ := TargetOffset;
  Buf.AddBytes(@Entry, SizeOf(Entry));
end;

procedure AddPackFolderHeader(Buf: TBufEC; EntryCount: Cardinal);
begin
  Buf.AddDWord(12 + EntryCount * PackEntryDiskSize);
  Buf.AddDWord(EntryCount);
  Buf.AddDWord(PackEntryDiskSize);
end;

procedure AddPackBlock(Buf: TBufEC; Source: PByte; ByteCount: Integer);
var
  Block: array of Byte;
  StoredSize: Integer;
begin
  SetLength(Block, ByteCount);
  StoredSize := OKGF_ZLib_Compress(@Block[0], Source, ByteCount, 0);
  Check(StoredSize > 0, 'Package block compresses');
  Buf.AddDWord(StoredSize);
  Buf.AddBytes(@Block[0], StoredSize);
end;

function PackedByte(Index: Integer): Byte;
begin
  Result := Byte((Index * 31) xor (Index shr 9));
end;

// Layout: root offset, root folder (DATA/, README.TXT), DATA folder (BIG.BIN), then data.
procedure BuildPackage(Buf: TBufEC; const Readme: AnsiString);
const
  RootOffset = 4;
  DataFolderOffset = RootOffset + 12 + 2 * PackEntryDiskSize;
  ReadmeOffset = DataFolderOffset + 12 + PackEntryDiskSize;
var
  Content: array of Byte;
  i, BigOffset: Integer;
begin
  BigOffset := ReadmeOffset + 4 + Length(Readme);
  Buf.AddDWord(RootOffset);
  AddPackFolderHeader(Buf, 2);
  AddPackEntry(Buf, 'Data', PackKindFolder, 0, DataFolderOffset);
  AddPackEntry(Buf, 'Readme.txt', PackKindRaw, Length(Readme), ReadmeOffset);
  AddPackFolderHeader(Buf, 1);
  AddPackEntry(Buf, 'Big.bin', PackKindChained, PackedFileSize, BigOffset);
  CheckInt(ReadmeOffset, Buf.DataSize, 'Package layout readme offset');
  Buf.AddDWord(Length(Readme));
  Buf.AddAnsiStringRaw(Readme);
  CheckInt(BigOffset, Buf.DataSize, 'Package layout data offset');
  Buf.AddDWord(PackedFileSize);
  SetLength(Content, PackedFileSize);
  for i := 0 to PackedFileSize - 1 do
    Content[i] := PackedByte(i);
  AddPackBlock(Buf, @Content[0], PackBlockSize);
  AddPackBlock(Buf, @Content[PackBlockSize], PackedFileSize - PackBlockSize);
end;

function CheckPackedRange(
    Pack: TPackFileEC;
    Slot: Integer;
    Offset: Integer;
    ByteCount: Integer;
    const Name: string
): Boolean;
var
  Bytes: array of Byte;
  i: Integer;
begin
  SetLength(Bytes, ByteCount);
  Result := Pack.ReadEntrySlot(Slot, @Bytes[0], ByteCount);
  Check(Result, Name + ' read');
  if not Result then
    Exit;
  for i := 0 to ByteCount - 1 do
    if Bytes[i] <> PackedByte(Offset + i) then
    begin
      Fail(Name, Format('byte %d differs', [Offset + i]));
      Result := False;
      Exit;
    end;
end;

procedure RunPackageTests;
const
  Readme = 'Package readme text';
var
  Buf: TBufEC;
  Pack: TPackFileEC;
  Slot: Integer;
  Text: AnsiString;
begin
  Buf := TBufEC.Create;
  Pack := TPackFileEC.Create;
  try
    BuildPackage(Buf, Readme);
    SaveBuffer(Buf, WorkPath('test.pkg'));
    Pack.SetPackagePath(AnsiString(WorkPath('test.pkg')));
    Check(Pack.Open, 'Package open');
    CheckInt(-1, Pack.OpenEntryByPath('missing.txt', 0), 'Package missing entry');

    Slot := Pack.OpenEntryByPath('readme.TXT', 0);
    Check(Slot >= 0, 'Package raw entry opens case-insensitively');
    CheckInt(Length(Readme), Pack.GetEntrySlotSize(Slot), 'Package raw entry size');
    SetLength(Text, Length(Readme));
    Check(Pack.ReadEntrySlot(Slot, PAnsiChar(Text), Length(Text)), 'Package raw entry read');
    CheckText(Readme, WideString(Text), 'Package raw entry content');
    Check(Pack.CloseEntrySlot(Slot), 'Package raw entry close');

    Slot := Pack.OpenEntryByPath('DATA\big.bin', 0);
    Check(Slot >= 0, 'Package chained entry opens');
    CheckInt(PackedFileSize, Pack.GetEntrySlotSize(Slot), 'Package chained entry size');
    // Sequential read across the block boundary, then a backward seek into block 0.
    CheckPackedRange(Pack, Slot, 0, PackedFileSize, 'Package chained sequential');
    Check(Pack.SeekEntrySlot(Slot, PackBlockSize - 10, 0), 'Package chained seek');
    CheckInt(PackBlockSize - 10, Pack.GetEntrySlotPosition(Slot), 'Package chained position');
    CheckPackedRange(Pack, Slot, PackBlockSize - 10, 20, 'Package chained seek read');
    Check(Pack.CloseEntrySlot(Slot), 'Package chained entry close');
    Check(Pack.Close, 'Package close');
  except
    on E: Exception do
      ReportException('Package', E);
  end;
  Pack.Free;
  Buf.Free;
end;

procedure RunCodecTests(const WorkDirectory: string);
begin
  Work := WorkDirectory;
  ForceDirectories(Work);
  // DAT loaders read through the package collection; its loose-file pack maps
  // absolute paths straight to the file system.
  InitializePackageCollection;
  try
    RunBlockParDatTests;
    RunBlockParTextTests;
    RunResourceDatTests;
    RunPackageTests;
  finally
    FinalizePackageCollection;
  end;
end;

end.

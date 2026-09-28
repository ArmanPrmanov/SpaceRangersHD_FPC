{$EXCESSPRECISION OFF}
unit NetProtocol;

// CHANGE: ENHANCEMENT - The multiplayer protocol (ROADMAP.md, Phase 5; docs/network.md,
// Messages): the message kinds, their payloads and the data hash that a host and a client
// must share. Payloads are TBufEC encodings; a kind is never renumbered, new kinds go at the
// end, and ProtocolVersion goes up when a payload changes.
interface
uses
  EC_Buf,
  aCommands,
  NetTransport;
const
  // CHANGE: ENHANCEMENT - 2: TalkRequest has a payload (remote dialogue).
  ProtocolVersion = 2;
  // The game a peer runs, for the host's log; the data hash decides whether it may join.
  GameVersionText = '2.1.2500';

  nkHello = 1;
  nkWelcome = 2;
  nkRefuse = 3;
  nkState = 4;
  nkFilm = 5;
  nkCommand = 6;
  nkAck = 7;
  nkStatus = 8;
  nkTalkRequest = 9;
  nkTalkDone = 10;
  nkChat = 11;
  nkBye = 12;
type
  // client -> host: who joins, with what.
  THelloMessage = record
    Protocol: Integer;
    GameVersion: WideString;
    DataHash: QWord;
    // The ranger name; a disconnected human whose ranger has it is taken back (rejoin).
    Name: WideString;
    Spectator: Boolean;
  end;
  // host -> client: the client's human.
  TWelcomeMessage = record
    HumanId: Integer;
    HostName: WideString;
  end;
  // host -> client: a state, whole (BaseSerial 0) or a delta against the state numbered
  // BaseSerial. The zstd bytes (NetDelta) follow the header to the end of the payload. States
  // are numbered by the host from 1: a join between two days sends a state of the same galaxy
  // day as the one before it, so the day cannot name a base.
  TStateHeader = record
    Serial: Integer;
    BaseSerial: Integer;
    // The galaxy day (TGalaxy.CurrentTurn).
    Day: Integer;
    // GalaxyStateHash of the state, taken on the host with its own human local.
    Hash: QWord;
  end;
  // host -> client: the film of a star's day (TEFilm.SaveToBuffer) follows the header.
  TFilmHeader = record
    Day: Integer;
    StarId: Integer;
  end;
  TStatusHuman = record
    Id: Integer;
    Name: WideString;
    Connected: Boolean;
    HoldsDay: Boolean;
  end;
  // host -> client: who the day waits for.
  TStatusMessage = record
    Humans: array of TStatusHuman;
    DayRunning: Boolean;
  end;
  TChatMessage = record
    SenderId: Integer;
    Text: WideString;
  end;
  // host -> client: the host's day asks the client's human something (docs/network.md, Remote
  // dialogue). The fields are the human's talk fields (THuman) as the turn thread set them;
  // the ship or planet is named by id (0: none). The client answers with commands and then
  // TalkDone, which has no payload.
  TTalkRequestMessage = record
    HumanId: Integer;
    ShipId: Integer;
    PlanetId: Integer;
    Scripted: Boolean;
    TalkType: Byte;
    Amount: Integer;
    Text: WideString;
  end;

function MessageKindName(Kind: TNetMessageKind): AnsiString;

var
  // Also told every network event NetLog writes; the headless runner prints them.
  NetLogHook: procedure(const Text: AnsiString);
// Writes a network event (a join, a refusal, a disconnect) to the game's log.
procedure NetLog(const Text: AnsiString);

procedure EncodeHello(const Message: THelloMessage; Buffer: TBufEC);
function DecodeHello(Buffer: TBufEC): THelloMessage;
procedure EncodeWelcome(const Message: TWelcomeMessage; Buffer: TBufEC);
function DecodeWelcome(Buffer: TBufEC): TWelcomeMessage;
procedure EncodeRefuse(const Reason: WideString; Buffer: TBufEC);
function DecodeRefuse(Buffer: TBufEC): WideString;
// Writes the header; the caller appends the compressed state.
procedure EncodeStateHeader(const Header: TStateHeader; Buffer: TBufEC);
// Reads the header and leaves Buffer at the compressed state.
function DecodeStateHeader(Buffer: TBufEC): TStateHeader;
// Writes the header; the caller appends the film.
procedure EncodeFilmHeader(const Header: TFilmHeader; Buffer: TBufEC);
// Reads the header and leaves Buffer at the film.
function DecodeFilmHeader(Buffer: TBufEC): TFilmHeader;
procedure EncodeCommandMessage(const Command: TPlayerCommand; Buffer: TBufEC);
function DecodeCommandMessage(Buffer: TBufEC): TPlayerCommand;
procedure EncodeAck(Day: Integer; Buffer: TBufEC);
function DecodeAck(Buffer: TBufEC): Integer;
procedure EncodeStatus(const Message: TStatusMessage; Buffer: TBufEC);
function DecodeStatus(Buffer: TBufEC): TStatusMessage;
procedure EncodeChat(const Message: TChatMessage; Buffer: TBufEC);
function DecodeChat(Buffer: TBufEC): TChatMessage;
procedure EncodeTalkRequest(const Message: TTalkRequestMessage; Buffer: TBufEC);
function DecodeTalkRequest(Buffer: TBufEC): TTalkRequestMessage;

// The hash of the game data a host and its clients must share (Hello): the packages
// INSTALL.TXT lists, CFG\Main.dat and CFG\CacheData.dat, the selected mods' names and their
// files. Settings and the language (its packages, Lang.dat, a mod's language files) are left
// out, so players with other languages can play together. Computed on first use, from the
// game directory (the current directory); it reads ~1.6 GB, at memory speed once cached.
function DataHash: QWord;
// The same over a list of files, in order: each file's name, size and bytes. Missing files
// count by name. Exposed for the unit tests.
function HashFiles(const Names: array of AnsiString): QWord;
implementation
uses
  SysUtils,
  Classes,
  Windows,
  EC_BlockPar,
  GR_Main,
  NetNative;

function MessageKindName(Kind: TNetMessageKind): AnsiString;
begin
  case Kind of
    nkHello: Result := 'Hello';
    nkWelcome: Result := 'Welcome';
    nkRefuse: Result := 'Refuse';
    nkState: Result := 'State';
    nkFilm: Result := 'Film';
    nkCommand: Result := 'Command';
    nkAck: Result := 'Ack';
    nkStatus: Result := 'Status';
    nkTalkRequest: Result := 'TalkRequest';
    nkTalkDone: Result := 'TalkDone';
    nkChat: Result := 'Chat';
    nkBye: Result := 'Bye';
  else
    Result := 'Kind' + IntToStr(Kind);
  end;
end;

procedure NetLog(const Text: AnsiString);
begin
  AppendLogLineThreadSafe('Network: ' + Text);
  if Assigned(NetLogHook) then
    NetLogHook(Text);
end;

procedure AddQWord(Buffer: TBufEC; Value: QWord);
begin
  Buffer.AddBytes(@Value, SizeOf(Value));
end;

function GetQWord(Buffer: TBufEC): QWord;
begin
  Buffer.ReadBytes(@Result, SizeOf(Result));
end;

procedure EncodeHello(const Message: THelloMessage; Buffer: TBufEC);
begin
  Buffer.AddInt32(Message.Protocol);
  Buffer.AddWideStringZ(Message.GameVersion);
  AddQWord(Buffer, Message.DataHash);
  Buffer.AddWideStringZ(Message.Name);
  Buffer.AddBoolean(Message.Spectator);
end;

function DecodeHello(Buffer: TBufEC): THelloMessage;
begin
  Result := Default(THelloMessage);
  Result.Protocol := Buffer.GetInt32;
  // A peer of another protocol may lay out the rest differently.
  if Result.Protocol <> ProtocolVersion then
    Exit;
  Result.GameVersion := Buffer.ReadWideString;
  Result.DataHash := GetQWord(Buffer);
  Result.Name := Buffer.ReadWideString;
  Result.Spectator := Buffer.GetBoolean;
end;

procedure EncodeWelcome(const Message: TWelcomeMessage; Buffer: TBufEC);
begin
  Buffer.AddInt32(Message.HumanId);
  Buffer.AddWideStringZ(Message.HostName);
end;

function DecodeWelcome(Buffer: TBufEC): TWelcomeMessage;
begin
  Result.HumanId := Buffer.GetInt32;
  Result.HostName := Buffer.ReadWideString;
end;

procedure EncodeRefuse(const Reason: WideString; Buffer: TBufEC);
begin
  Buffer.AddWideStringZ(Reason);
end;

function DecodeRefuse(Buffer: TBufEC): WideString;
begin
  Result := Buffer.ReadWideString;
end;

procedure EncodeStateHeader(const Header: TStateHeader; Buffer: TBufEC);
begin
  Buffer.AddInt32(Header.Serial);
  Buffer.AddInt32(Header.BaseSerial);
  Buffer.AddInt32(Header.Day);
  AddQWord(Buffer, Header.Hash);
end;

function DecodeStateHeader(Buffer: TBufEC): TStateHeader;
begin
  Result.Serial := Buffer.GetInt32;
  Result.BaseSerial := Buffer.GetInt32;
  Result.Day := Buffer.GetInt32;
  Result.Hash := GetQWord(Buffer);
end;

procedure EncodeFilmHeader(const Header: TFilmHeader; Buffer: TBufEC);
begin
  Buffer.AddInt32(Header.Day);
  Buffer.AddInt32(Header.StarId);
end;

function DecodeFilmHeader(Buffer: TBufEC): TFilmHeader;
begin
  Result.Day := Buffer.GetInt32;
  Result.StarId := Buffer.GetInt32;
end;

procedure EncodeCommandMessage(const Command: TPlayerCommand; Buffer: TBufEC);
begin
  EncodeCommand(Command, Buffer);
end;

function DecodeCommandMessage(Buffer: TBufEC): TPlayerCommand;
begin
  Result := DecodeCommand(Buffer);
end;

procedure EncodeAck(Day: Integer; Buffer: TBufEC);
begin
  Buffer.AddInt32(Day);
end;

function DecodeAck(Buffer: TBufEC): Integer;
begin
  Result := Buffer.GetInt32;
end;

procedure EncodeStatus(const Message: TStatusMessage; Buffer: TBufEC);
var
  I: Integer;
begin
  Buffer.AddBoolean(Message.DayRunning);
  Buffer.AddInt32(Length(Message.Humans));
  for I := 0 to High(Message.Humans) do
  begin
    Buffer.AddInt32(Message.Humans[I].Id);
    Buffer.AddWideStringZ(Message.Humans[I].Name);
    Buffer.AddBoolean(Message.Humans[I].Connected);
    Buffer.AddBoolean(Message.Humans[I].HoldsDay);
  end;
end;

function DecodeStatus(Buffer: TBufEC): TStatusMessage;
var
  I, Count: Integer;
begin
  Result := Default(TStatusMessage);
  Result.DayRunning := Buffer.GetBoolean;
  Count := Buffer.GetInt32;
  if (Count < 0) or (Count > 65535) then
    raise Exception.Create('Bad status message');
  SetLength(Result.Humans, Count);
  for I := 0 to Count - 1 do
  begin
    Result.Humans[I].Id := Buffer.GetInt32;
    Result.Humans[I].Name := Buffer.ReadWideString;
    Result.Humans[I].Connected := Buffer.GetBoolean;
    Result.Humans[I].HoldsDay := Buffer.GetBoolean;
  end;
end;

procedure EncodeChat(const Message: TChatMessage; Buffer: TBufEC);
begin
  Buffer.AddInt32(Message.SenderId);
  Buffer.AddWideStringZ(Message.Text);
end;

function DecodeChat(Buffer: TBufEC): TChatMessage;
begin
  Result.SenderId := Buffer.GetInt32;
  Result.Text := Buffer.ReadWideString;
end;

procedure EncodeTalkRequest(const Message: TTalkRequestMessage; Buffer: TBufEC);
begin
  Buffer.AddInt32(Message.HumanId);
  Buffer.AddInt32(Message.ShipId);
  Buffer.AddInt32(Message.PlanetId);
  Buffer.AddBoolean(Message.Scripted);
  Buffer.AddByte(Message.TalkType);
  Buffer.AddInt32(Message.Amount);
  Buffer.AddWideStringZ(Message.Text);
end;

function DecodeTalkRequest(Buffer: TBufEC): TTalkRequestMessage;
begin
  Result := Default(TTalkRequestMessage);
  Result.HumanId := Buffer.GetInt32;
  Result.ShipId := Buffer.GetInt32;
  Result.PlanetId := Buffer.GetInt32;
  Result.Scripted := Buffer.GetBoolean;
  Result.TalkType := Buffer.GetByte;
  Result.Amount := Buffer.GetInt32;
  Result.Text := Buffer.ReadWideString;
end;

{ Data hash }

const
  HashChunkSize = 1024 * 1024;

procedure HashText(var Hash: QWord; const Text: AnsiString);
begin
  if Text <> '' then
    Hash := sr_hash64(@Text[1], Length(Text), Hash)
  else
    Hash := sr_hash64(nil, 0, Hash);
end;

// Chains the file's name (as the game names it), size and bytes into Hash.
procedure HashFile(var Hash: QWord; const Name: AnsiString; Chunk: Pointer);
var
  Stream: TFileStream;
  Count: Integer;
  Size: Int64;
begin
  HashText(Hash, LowerCase(StringReplace(Name, '/', '\', [rfReplaceAll])));
  if not SysUtils.FileExists(NativePath(Name)) then
  begin
    HashText(Hash, '<missing>');
    Exit;
  end;
  // The game has its packages open already.
  Stream := TFileStream.Create(NativePath(Name), fmOpenRead or fmShareDenyNone);
  try
    Size := Stream.Size;
    Hash := sr_hash64(@Size, SizeOf(Size), Hash);
    repeat
      Count := Stream.Read(Chunk^, HashChunkSize);
      if Count > 0 then
        Hash := sr_hash64(Chunk, Count, Hash);
    until Count < HashChunkSize;
  finally
    Stream.Free
  end;
end;

function HashFiles(const Names: array of AnsiString): QWord;
var
  Chunk: Pointer;
  I: Integer;
begin
  Result := 0;
  GetMem(Chunk, HashChunkSize);
  try
    for I := 0 to High(Names) do
      HashFile(Result, Names[I], Chunk);
  finally
    FreeMem(Chunk);
  end;
end;

// The files of a mod folder, sorted, without its language files: install lists for a
// language (Install_*.txt) and language data (CFG\<language>\).
procedure CollectModFiles(const Directory, Relative: AnsiString; Files: TStringList);
var
  Search: TSearchRec;
  Name, Path: AnsiString;
begin
  if SysUtils.FindFirst(NativePath(Directory + Relative + '*'), faAnyFile, Search) <> 0 then
    Exit;
  try
    repeat
      Name := Search.Name;
      if (Name = '.') or (Name = '..') then
        Continue;
      Path := Relative + Name;
      if (Search.Attr and faDirectory) <> 0 then
      begin
        // CFG's subdirectories hold one language each.
        if not SameText(Relative, 'CFG\') then
          CollectModFiles(Directory, Path + '\', Files);
      end
      else if not (SameText(Copy(Name, 1, 8), 'Install_') and SameText(ExtractFileExt(Name), '.txt')) then
        Files.Add(Directory + Path);
    until SysUtils.FindNext(Search) <> 0;
  finally
    SysUtils.FindClose(Search);
  end;
end;

procedure CollectDataFiles(Files: TStringList);
var
  Block: TBlockParEC;
  I: Integer;
  Mods, ModName: WideString;
  ModFiles: TStringList;
begin
  if InstallConfig <> nil then
  begin
    Block := InstallConfig.GetBlock('Packages');
    if Block <> nil then
      for I := 0 to Block.GetParamCount - 1 do
        Files.Add(UTF8Encode(Block.GetParamValue(I)));
  end;
  Files.Add('CFG\Main.dat');
  Files.Add('CFG\CacheData.dat');
  Mods := SelectedMods;
  while Mods <> '' do
  begin
    I := Pos(',', Mods);
    if I = 0 then
      I := Length(Mods) + 1;
    ModName := Trim(Copy(Mods, 1, I - 1));
    Delete(Mods, 1, I);
    if ModName = '' then
      Continue;
    ModFiles := TStringList.Create;
    try
      ModFiles.Sorted := False;
      CollectModFiles('Mods\' + UTF8Encode(ModName) + '\', '', ModFiles);
      ModFiles.CaseSensitive := False;
      ModFiles.Sort;
      Files.AddStrings(ModFiles);
    finally
      ModFiles.Free;
    end;
  end;
end;

var
  DataHashKnown: Boolean;
  DataHashValue: QWord;

function DataHash: QWord;
var
  Files: TStringList;
  Names: array of AnsiString;
  I: Integer;
begin
  if DataHashKnown then
    Exit(DataHashValue);
  Files := TStringList.Create;
  try
    CollectDataFiles(Files);
    SetLength(Names, Files.Count);
    for I := 0 to Files.Count - 1 do
      Names[I] := Files[I];
  finally
    Files.Free;
  end;
  DataHashValue := HashFiles(Names);
  // Two installs with the same files but other mods selected differ.
  HashText(DataHashValue, LowerCase(UTF8Encode(SelectedMods)));
  DataHashKnown := True;
  Result := DataHashValue;
end;

end.

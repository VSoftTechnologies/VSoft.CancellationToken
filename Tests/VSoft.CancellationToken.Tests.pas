unit VSoft.CancellationToken.Tests;

interface

uses
  DUnitX.TestFramework,
  VSoft.CancellationToken;

type
  [TestFixture]
  TCancellationTokenTests = class
  private
    FTokenSource : ICancellationTokenSource;

  public

    //A new source for every test, so no test depends on the state another
    //one left behind.
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestCancel;

    [Test]
    procedure TestCancelUsingHandle;

    // Cancel on one thread racing Reset on another must never leave the
    // event set while IsCancelled is False (or the reverse).
    [Test]
    procedure TestCancelResetRace;

  end;

  [TestFixture]
  TCancellationTokenFactoryTests = class
  public
    //Puts the default token class back after each test.
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestRegisterNilRaises;

    [Test]
    procedure TestFactoryRejectsClassWithoutTokenInterface;

    [Test]
    procedure TestFactoryRejectsClassWithoutManageInterface;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  System.Diagnostics,
  WinApi.Windows,
  VSoft.CancellationToken.Impl;

const
  cWorkerTimeout = 10000;
  cRaceRounds = 50000;
  cRaceJitter = 64;

type
  //Implements neither token interface.
  TNoInterfaceToken = class(TCancellationTokenBase)
  public
    class var LiveCount : integer;
    constructor Create;override;
    destructor Destroy;override;
  end;

  //Implements ICancellationToken but not ICancellationTokenManage.
  TReadOnlyToken = class(TCancellationTokenBase, ICancellationToken)
  protected
    {$IFDEF MSWINDOWS}
    function GetHandle : THandle;
    {$ELSE}
    function GetEvent : TEvent;
    {$ENDIF}
    function IsCancelled : boolean;
    function WaitFor(Timeout : Cardinal) : TWaitResult;
  public
    class var LiveCount : integer;
    constructor Create;override;
    destructor Destroy;override;
  end;

{ TNoInterfaceToken }

constructor TNoInterfaceToken.Create;
begin
  TInterlocked.Increment(LiveCount);
end;

destructor TNoInterfaceToken.Destroy;
begin
  TInterlocked.Decrement(LiveCount);
  inherited;
end;

{ TReadOnlyToken }

constructor TReadOnlyToken.Create;
begin
  TInterlocked.Increment(LiveCount);
end;

destructor TReadOnlyToken.Destroy;
begin
  TInterlocked.Decrement(LiveCount);
  inherited;
end;

{$IFDEF MSWINDOWS}
function TReadOnlyToken.GetHandle : THandle;
begin
  result := 0;
end;
{$ELSE}
function TReadOnlyToken.GetEvent : TEvent;
begin
  result := nil;
end;
{$ENDIF}

function TReadOnlyToken.IsCancelled : boolean;
begin
  result := false;
end;

function TReadOnlyToken.WaitFor(Timeout : Cardinal) : TWaitResult;
begin
  result := wrError;
end;

{ TCancellationTokenTests }

procedure TCancellationTokenTests.Setup;
begin
  FTokenSource := TCancellationTokenSourceFactory.Create;
end;

procedure TCancellationTokenTests.TearDown;
begin
  FTokenSource := nil;
end;

procedure TCancellationTokenTests.TestCancel;
var
  token : ICancellationToken;
  started : TEvent;
  sawIt : TEvent;
  worker : TThread;
begin
  token := FTokenSource.Token;
  started := TEvent.Create(nil, true, false, '');
  sawIt := TEvent.Create(nil, true, false, '');
  try
    //The worker reports through events, not a shared flag, and gives up
    //after cWorkerTimeout instead of polling for ever.
    worker := TThread.CreateAnonymousThread(
      procedure
      var
        stopwatch : TStopwatch;
      begin
        stopwatch := TStopwatch.StartNew;
        started.SetEvent;
        while (not token.IsCancelled) and (stopwatch.ElapsedMilliseconds < cWorkerTimeout) do
          TThread.Sleep(1);
        if token.IsCancelled then
          sawIt.SetEvent;
      end);
    worker.FreeOnTerminate := false;
    try
      worker.Start;
      Assert.AreEqual<TWaitResult>(wrSignaled, started.WaitFor(cWorkerTimeout), 'The worker did not start');
      Assert.AreEqual<TWaitResult>(wrTimeout, sawIt.WaitFor(0), 'The worker saw a cancellation before Cancel');
      FTokenSource.Cancel;
      Assert.AreEqual<TWaitResult>(wrSignaled, sawIt.WaitFor(cWorkerTimeout), 'The worker never saw IsCancelled = True');
    finally
      worker.WaitFor;
      worker.Free;
    end;
  finally
    sawIt.Free;
    started.Free;
  end;
end;


procedure TCancellationTokenTests.TestCancelUsingHandle;
var
  token : ICancellationToken;
  other : TEvent;
  worker : TThread;
  waitResult : Cardinal;
begin
  token := FTokenSource.Token;
  other := TEvent.Create(nil, false, false, '');
  waitResult := WAIT_FAILED;
  try
    Assert.AreEqual<Cardinal>(WAIT_TIMEOUT, WaitForSingleObject(token.Handle, 0), 'The handle was signalled before Cancel');
    worker := TThread.CreateAnonymousThread(
      procedure
      var
        handles : array[0..1] of THandle;
      begin
        handles[0] := token.Handle;
        handles[1] := other.Handle;
        //One wait with a limit: a timeout or WAIT_FAILED ends the worker
        //and is reported, instead of looping for ever.
        waitResult := WaitForMultipleObjects(2, @handles, false, cWorkerTimeout);
      end);
    worker.FreeOnTerminate := false;
    try
      worker.Start;
      FTokenSource.Cancel;
    finally
      worker.WaitFor;
      worker.Free;
    end;
    Assert.AreEqual<Cardinal>(WAIT_OBJECT_0, waitResult, 'The wait did not end on the token''s handle');
  finally
    other.Free;
  end;
end;

{ TCancellationTokenFactoryTests }

procedure TCancellationTokenFactoryTests.TearDown;
begin
  TCancellationTokenSourceFactory.RegisterTokenClass(TCancellationToken);
end;

procedure TCancellationTokenFactoryTests.TestRegisterNilRaises;
var
  source : ICancellationTokenSource;
begin
  Assert.WillRaise(
    procedure
    begin
      TCancellationTokenSourceFactory.RegisterTokenClass(nil);
    end, EArgumentNilException, 'RegisterTokenClass(nil) was accepted');
  //The registered class is still the default one.
  source := TCancellationTokenSourceFactory.Create;
  source.Cancel;
  Assert.IsTrue(source.Token.IsCancelled);
end;

procedure TCancellationTokenFactoryTests.TestFactoryRejectsClassWithoutTokenInterface;
var
  msg : string;
begin
  msg := '';
  TNoInterfaceToken.LiveCount := 0;
  TCancellationTokenSourceFactory.RegisterTokenClass(TNoInterfaceToken);
  try
    TCancellationTokenSourceFactory.Create;
    Assert.Fail('Create accepted a class with no token interface');
  except
    on E : EIntfCastError do
      msg := E.Message;
  end;
  Assert.AreEqual(0, TNoInterfaceToken.LiveCount, 'The rejected instance was leaked');
  Assert.AreEqual('Registered Token class does not implement required interface ICancellationToken', msg, false);
end;

procedure TCancellationTokenFactoryTests.TestFactoryRejectsClassWithoutManageInterface;
var
  msg : string;
begin
  msg := '';
  TReadOnlyToken.LiveCount := 0;
  TCancellationTokenSourceFactory.RegisterTokenClass(TReadOnlyToken);
  try
    TCancellationTokenSourceFactory.Create;
    Assert.Fail('Create accepted a class without ICancellationTokenManage');
  except
    on E : EIntfCastError do
      msg := E.Message;
  end;
  Assert.AreEqual(0, TReadOnlyToken.LiveCount, 'The rejected instance was leaked');
  Assert.AreEqual('Registered Token class does not implement required interface ICancellationTokenManage', msg, false);
end;

procedure TCancellationTokenTests.TestCancelResetRace;
var
  source : ICancellationTokenSource;
  token : ICancellationToken;
  worker : TThread;
  roundNo : integer;
  done : integer;
  stop : integer;
  i : integer;
  seed : UInt64;
  stopwatch : TStopwatch;
  eventSet : boolean;
  mismatches : integer;
  firstBad : integer;
  endedSet : integer;
  endedClear : integer;
begin
  //A source of its own: the fixture's one is shared with the other tests.
  source := TCancellationTokenSourceFactory.Create;
  token := source.Token;
  roundNo := 0;
  done := 0;
  stop := 0;
  mismatches := 0;
  firstBad := 0;
  endedSet := 0;
  endedClear := 0;

  //Calls Cancel once per round, after a pseudo-random spin, so it lands
  //anywhere relative to the Reset on the test thread.
  worker := TThread.CreateAnonymousThread(
    procedure
    var
      seen : integer;
      current : integer;
      workerSeed : UInt64;
    begin
      seen := 0;
      workerSeed := 1;
      while TInterlocked.CompareExchange(stop, 0, 0) = 0 do
      begin
        current := TInterlocked.CompareExchange(roundNo, 0, 0);
        if current <> seen then
        begin
          seen := current;
          workerSeed := (workerSeed * 1664525 + 1013904223) and $FFFFFFFF;
          TThread.SpinWait((workerSeed shr 16) mod cRaceJitter);
          source.Cancel;
          TInterlocked.Increment(done);
        end;
      end;
    end);
  worker.FreeOnTerminate := false;
  worker.Start;
  try
    stopwatch := TStopwatch.StartNew;
    seed := 12345;
    for i := 1 to cRaceRounds do
    begin
      TInterlocked.Increment(roundNo);
      seed := (seed * 1664525 + 1013904223) and $FFFFFFFF;
      TThread.SpinWait((seed shr 16) mod cRaceJitter);
      source.Reset;
      //Wait for this round's Cancel, then the token must be consistent.
      while TInterlocked.CompareExchange(done, 0, 0) < i do
        if stopwatch.ElapsedMilliseconds > 60000 then
          Assert.Fail(Format('The Cancel thread stalled in round %d', [i]));
      eventSet := token.WaitFor(0) = wrSignaled;
      if token.IsCancelled <> eventSet then
      begin
        Inc(mismatches);
        if firstBad = 0 then
          firstBad := i;
      end;
      if eventSet then
        Inc(endedSet)
      else
        Inc(endedClear);
    end;
  finally
    TInterlocked.Exchange(stop, 1);
    worker.WaitFor;
    worker.Free;
  end;

  Assert.AreEqual(0, mismatches, Format('%d of %d rounds ended with IsCancelled <> the event state (first: round %d)',
                                        [mismatches, cRaceRounds, firstBad]));
  //Both outcomes must occur, or the calls never really raced.
  Assert.IsTrue(endedSet > 0, 'No round ended cancelled');
  Assert.IsTrue(endedClear > 0, 'No round ended reset');
end;

initialization
  TDUnitX.RegisterTestFixture(TCancellationTokenTests);
  TDUnitX.RegisterTestFixture(TCancellationTokenFactoryTests);

end.

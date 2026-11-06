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
  Assert.IsTrue(Pos('ICancellationToken', msg) > 0, 'The error does not name the missing interface: ' + msg);
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
  Assert.IsTrue(Pos('ICancellationTokenManage', msg) > 0, 'The error does not name the missing interface: ' + msg);
end;

initialization
  TDUnitX.RegisterTestFixture(TCancellationTokenTests);
  TDUnitX.RegisterTestFixture(TCancellationTokenFactoryTests);

end.

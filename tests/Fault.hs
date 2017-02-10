module Fault where

import Data.Monoid ((<>))
import Data.Foldable
import Control.Monad
import Data.Maybe
import Data.Either
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BS
import qualified Data.Vector as V
import System.Socket (SocketException(..))
import System.Mem.Weak (Weak, deRefWeak)
import Control.Concurrent (throwTo)
import Control.Concurrent.Async
import Control.Exception

import Test.Tasty
import Test.Tasty.HUnit

import Database.PostgreSQL.Driver.Connection
import Database.PostgreSQL.Driver.RawConnection
import Database.PostgreSQL.Driver.StatementStorage
import Database.PostgreSQL.Driver.Query
import Database.PostgreSQL.Driver.Error
import Database.PostgreSQL.Protocol.Types

import Connection

longQuery :: Query
longQuery = Query "SELECT pg_sleep(5)" V.empty Text Text NeverCache

testFaults :: TestTree
testFaults = testGroup "Faults"
    [ makeInterruptTest "Single batch by waitReadyForQuery"
        testBatchReadyForQuery
    , makeInterruptTest "Single batch by readNextData "
        testBatchNextData
    , makeInterruptTest "Simple Query"
        testSimpleQuery
    ]
  where
    makeInterruptTest name action = testGroup name $
        map (\(caseName, interruptAction) ->
            testCase caseName $ action interruptAction)
        [ ("close", close)
        , ("close socket", closeSocket)
        , ("socket exception", throwSocketException)
        , ("other exception", throwOtherException)
        ]

testBatchReadyForQuery :: (Connection -> IO ()) -> IO ()
testBatchReadyForQuery interruptAction = withConnection $ \c -> do
    sendBatchAndSync c [longQuery]
    interruptAction c
    r <- waitReadyForQuery c
    assertUnexpected r

testBatchNextData :: (Connection -> IO ()) -> IO ()
testBatchNextData interruptAction = withConnection $ \c -> do
    sendBatchAndSync c [longQuery]
    interruptAction c
    r <- readNextData c
    assertUnexpected r

testSimpleQuery :: (Connection -> IO ()) -> IO ()
testSimpleQuery interruptAction = withConnection $ \c -> do
    asyncVar <- async $ sendSimpleQuery c "SELECT pg_sleep(5)"
    interruptAction c
    r <- wait asyncVar
    assertUnexpected r

closeSocket :: Connection -> IO ()
closeSocket = rClose . connRawConnection

throwSocketException :: Connection -> IO ()
throwSocketException conn = do
    let exc = SocketException 2
    maybe (pure ()) (`throwTo` exc) =<< deRefWeak (connReceiverThread conn)

throwOtherException :: Connection -> IO ()
throwOtherException conn = do
    let exc = PatternMatchFail "custom exc"
    maybe (pure ()) (`throwTo` exc) =<< deRefWeak (connReceiverThread conn)

assertUnexpected :: Show a => Either Error a -> Assertion
assertUnexpected (Left (UnexpectedError _)) = pure ()
assertUnexpected (Right v) = assertFailure $
    "Expected Unexpected error, but got " ++ show v

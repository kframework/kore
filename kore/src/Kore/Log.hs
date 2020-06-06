{- |
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

-}

module Kore.Log
    ( koreLogFilters
    , koreLogTransformer
    , withLogger
    , emptyLogger
    , stderrLogger
    , swappableLogger
    , makeKoreLogger
    , Colog.logTextStderr
    , Colog.logTextHandle
    , runKoreLog
    , archiveDirectoryReport
    , module Log
    , module KoreLogOptions
    ) where

import Prelude.Kore

import qualified Codec.Archive.Tar as Tar
import qualified Codec.Compression.GZip as GZip
import Colog
    ( LogAction (..)
    )
import qualified Colog
import Control.Concurrent.Async
    ( async
    )
import Control.Concurrent.Async as Async
import Control.Concurrent.MVar
import Control.Concurrent.STM
    ( atomically
    , newTChanIO
    , readTChan
    , writeTChan
    )
import Control.Exception
    ( BlockedIndefinitelyOnSTM (..)
    )
import Control.Monad
    ( forever
    )
import Control.Monad.Catch
    ( MonadMask
    )
import qualified Control.Monad.Catch as Exception
import Control.Monad.Cont
    ( ContT (..)
    , runContT
    )
import qualified Data.ByteString.Lazy as BS
import Data.Foldable
    ( toList
    )
import Data.Functor.Contravariant
    ( contramap
    )
import Data.String
    ( IsString
    , fromString
    )
import Data.Text
    ( Text
    )
import Data.Time.Clock
    ( getCurrentTime
    )
import Data.Time.Format
    ( defaultTimeLocale
    , formatTime
    )
import Data.Time.LocalTime
    ( LocalTime
    , getCurrentTimeZone
    , utcToLocalTime
    )
import qualified Pretty

import Kore.Log.DebugSolver
    ( DebugSolverOptions (DebugSolverOptions)
    , solverTranscriptLogger
    )
import qualified Kore.Log.DebugSolver as DebugSolver.DoNotUse
import Kore.Log.KoreLogOptions as KoreLogOptions
import Kore.Log.Registry
    ( lookupTextFromTypeWithError
    , typeOfSomeEntry
    )
import Kore.Log.SQLite
import Log
import System.Directory
    ( listDirectory
    )
import System.FilePath.Posix
    ( (<.>)
    , (</>)
    )
import System.IO
    ( hPutStrLn
    , stderr
    )

-- | Internal type used to add timestamps to a 'LogMessage'.
data WithTimestamp = WithTimestamp ActualEntry LocalTime

-- | Generates an appropriate logger for the given 'KoreLogOptions'. It uses
-- the CPS style because some outputters require cleanup (e.g. files).
withLogger
    :: FilePath
    -> KoreLogOptions
    -> (LogAction IO ActualEntry -> IO a)
    -> IO a
withLogger reportDirectory koreLogOptions = runContT $ do
    mainLogger <- ContT $ withMainLogger reportDirectory koreLogOptions
    let KoreLogOptions { debugSolverOptions } = koreLogOptions
    smtSolverLogger <- ContT $ withSmtSolverLogger debugSolverOptions
    let KoreLogOptions { logSQLiteOptions } = koreLogOptions
    logSQLite <- ContT $ withLogSQLite logSQLiteOptions
    return $ mainLogger <> smtSolverLogger <> logSQLite

withMainLogger
    :: FilePath
    -> KoreLogOptions
    -> (LogAction IO ActualEntry -> IO a)
    -> IO a
withMainLogger reportDirectory koreLogOptions = runContT $ do
    let KoreLogOptions { exeName } = koreLogOptions
        bugReportLogFile = reportDirectory </> getExeName exeName <.> "log"
    bugReportLogAction <- ContT $ Colog.withLogTextFile bugReportLogFile
    userLogAction <-
        case logType koreLogOptions of
            LogStdErr -> pure Colog.logTextStderr
            LogFileText logFile -> ContT $ Colog.withLogTextFile logFile
    let KoreLogOptions { timestampsSwitch } = koreLogOptions
        logAction =
            userLogAction <> bugReportLogAction
            & makeKoreLogger exeName timestampsSwitch
            & koreLogFilters koreLogOptions
            & koreLogTransformer koreLogOptions
    pure logAction

withSmtSolverLogger
    :: DebugSolverOptions -> (LogAction IO ActualEntry -> IO a) -> IO a
withSmtSolverLogger DebugSolverOptions {logFile} continue =
    case logFile of
        Nothing -> continue mempty
        Just filename -> Colog.withLogTextFile filename
            $ continue . solverTranscriptLogger

koreLogTransformer
    :: KoreLogOptions
    -> LogAction m ActualEntry
    -> LogAction m ActualEntry
koreLogTransformer koreLogOptions baseLogger =
    Colog.cmap
        ( warningsToErrors warningSwitch
        )
        baseLogger
  where
    KoreLogOptions { warningSwitch } = koreLogOptions

    warningsToErrors :: WarningSwitch -> ActualEntry -> ActualEntry
    warningsToErrors AsError entry@ActualEntry { actualEntry }
        | entrySeverity actualEntry == Warning =
            error . show . longDoc $ actualEntry
        | otherwise = entry
    warningsToErrors AsWarning entry = entry

koreLogFilters
    :: Applicative m
    => KoreLogOptions
    -> LogAction m ActualEntry
    -> LogAction m ActualEntry
koreLogFilters koreLogOptions baseLogger =
    Colog.cfilter
        (\entry ->
            filterEntry logEntries entry
            || filterSeverity logLevel entry
            || selectDebugApplyEquation debugApplyEquationOptions entry
            || selectDebugAttemptEquation debugAttemptEquationOptions entry
            || selectDebugEquation debugEquationOptions entry
        )
    baseLogger
  where
    KoreLogOptions { logLevel, logEntries } = koreLogOptions
    KoreLogOptions { debugApplyEquationOptions } = koreLogOptions
    KoreLogOptions { debugAttemptEquationOptions } = koreLogOptions
    KoreLogOptions { debugEquationOptions } = koreLogOptions

{- | Select the log entry types present in the active set.
 -}
filterEntry
    :: EntryTypes
    -> ActualEntry
    -> Bool
filterEntry logEntries ActualEntry { actualEntry } =
    typeOfSomeEntry actualEntry `elem` logEntries

{- | Select log entries with 'Severity' greater than or equal to the level.
 -}
filterSeverity
    :: Severity
    -> ActualEntry
    -> Bool
filterSeverity level ActualEntry { actualEntry = SomeEntry entry } =
    entrySeverity entry >= level

-- | Run a 'LoggerT' with the given options.
runKoreLog :: FilePath -> KoreLogOptions -> LoggerT IO a -> IO a
runKoreLog reportDirectory options loggerT =
    withLogger reportDirectory options $ \logAction ->
    withAsyncLogger logAction $ \asyncLogAction ->
        runLoggerT loggerT asyncLogAction

withAsyncLogger
    :: LogAction IO a
    -> (LogAction IO a -> IO b)
    -> IO b
withAsyncLogger logAction continue = do
    tChan <- newTChanIO
    let asyncLogAction = LogAction (atomically . writeTChan tChan)
    logAsync <- async $ untilDone $ do
        a <- atomically $ readTChan tChan
        logAction Colog.<& a
    mainAsync <- async $ continue asyncLogAction
    (_, b) <- tryAgain $ Async.waitBoth logAsync mainAsync
    return b
  where
    handleBlockedIndefinitelyOnSTM handler =
        Exception.handle $ \BlockedIndefinitelyOnSTM -> handler
    ignore = return ()
    untilDone = handleBlockedIndefinitelyOnSTM ignore . forever
    tryAgain action = handleBlockedIndefinitelyOnSTM action action

-- Creates a kore logger which:
--     * adds timestamps
--     * formats messages: "<exe-name>: [<timestamp>] <severity> (<entry-type>): <message>"
makeKoreLogger
    :: forall m
    .  MonadIO m
    => ExeName
    -> TimestampsSwitch
    -> LogAction m Text
    -> LogAction m ActualEntry
makeKoreLogger exeName timestampSwitch logToText =
    Colog.cmapM withTimestamp
    $ contramap messageToText logToText
  where
    messageToText :: WithTimestamp -> Text
    messageToText (WithTimestamp entry localTime) =
        Pretty.renderText
        . Pretty.layoutPretty Pretty.defaultLayoutOptions
        $ prettyActualEntry timestamp entry
      where
        timestamp =
            case timestampSwitch of
                TimestampsDisable -> Nothing
                TimestampsEnable ->
                    Just $ Pretty.brackets (formattedTime localTime)
    exeName' = Pretty.pretty exeName <> Pretty.colon
    formattedTime = formatLocalTime "%Y-%m-%d %H:%M:%S%Q"
    prettyActualEntry timestamp ActualEntry { actualEntry, entryContext } =
        (Pretty.vsep . concat)
        [ [header]
        , indent <$> context'
        , indent <$> [longDoc actualEntry]
        ]
      where
        header =
            (Pretty.hsep . catMaybes)
            [ Just exeName'
            , timestamp
            , Just severity'
            , Just (Pretty.parens $ type' actualEntry)
            ]
            <> Pretty.colon
        severity' = prettySeverity (entrySeverity actualEntry)
        type' entry =
            Pretty.pretty
            $ lookupTextFromTypeWithError
            $ typeOfSomeEntry entry
        context' =
            mapMaybe
                addTypeToDoc
                entryContext
                & toList
        addTypeToDoc se =
            fmap (\doc ->
                Pretty.hsep [Pretty.parens (type' se), doc <> Pretty.colon])
            . shortDoc
            $ se
    indent = Pretty.indent 4

-- | Adds the current timestamp to a log entry.
withTimestamp :: MonadIO io => ActualEntry -> io WithTimestamp
withTimestamp msg = WithTimestamp msg <$> getLocalTime

-- Helper to get the local time in 'MonadIO'.
getLocalTime :: MonadIO m => m LocalTime
getLocalTime =
    liftIO $ utcToLocalTime <$> getCurrentTimeZone <*> getCurrentTime

-- Formats the local time using the provided format string.
formatLocalTime :: IsString s => String -> LocalTime -> s
formatLocalTime format = fromString . formatTime defaultTimeLocale format

emptyLogger :: Applicative m => LogAction m msg
emptyLogger = mempty

stderrLogger
    :: MonadIO io
    => ExeName
    -> TimestampsSwitch
    -> LogAction io ActualEntry
stderrLogger exeName timestampsSwitch =
    makeKoreLogger exeName timestampsSwitch Colog.logTextStderr

{- | @swappableLogger@ delegates to the logger contained in the 'MVar'.

This allows the logger to be "swapped" during execution. (It also automatically
makes the logger thread-safe.)

 -}
swappableLogger
    :: (MonadIO m, MonadMask m)
    => MVar (LogAction m a)
    -> LogAction m a
swappableLogger mvar =
    Colog.LogAction $ Exception.bracket acquire release . worker
  where
    acquire = liftIO $ takeMVar mvar
    release = liftIO . putMVar mvar
    worker a logAction = Colog.unLogAction logAction a

archiveDirectoryReport
    :: FilePath   -- ^ Path of the \".tar.gz\" file to write.
    -> FilePath   -- ^ Directory to archive
    -> IO ()
archiveDirectoryReport tar base = do
    contents <- listDirectory base
    BS.writeFile (tar <> ".tar.gz") . GZip.compress . Tar.write
        =<< Tar.pack base contents
    hPutStrLn stderr $ "\nCreated " <> tar <> ".tar.gz"

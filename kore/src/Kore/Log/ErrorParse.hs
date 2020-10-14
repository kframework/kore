{- |
Copyright   : (c) Runtime Verification, 2020
License     : NCSA

-}

module Kore.Log.ErrorParse
    ( ErrorParse (..)
    , errorParse
    ) where

import Prelude.Kore

import Control.Monad.Catch
    ( Exception (..)
    , MonadThrow
    , throwM
    )
import Pretty

import Log

newtype ErrorParse = ErrorParse { message :: String }
    deriving Show

instance Exception ErrorParse where
    toException = toException . SomeEntry
    fromException exn =
        fromException exn >>= fromEntry

instance Pretty ErrorParse where
    pretty ErrorParse { message } =
        Pretty.pretty message

instance Entry ErrorParse where
    entrySeverity _ = Error

errorParse :: MonadThrow log => String -> log a
errorParse message =
    throwM ErrorParse { message }

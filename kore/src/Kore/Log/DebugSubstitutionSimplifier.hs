{- |
Copyright   : (c) Runtime Verification, 2020
License     : NCSA

-}
module Kore.Log.DebugSubstitutionSimplifier
    ( DebugSubstitutionSimplifier (..)
    , whileDebugSubstitutionSimplifier
    , debugSubstitutionSimplifierResult
    ) where

import Prelude.Kore

import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Log

import Pretty
    ( Pretty (..)
    )
import qualified SQL

data DebugSubstitutionSimplifier
    = WhileSimplifySubstitution
    | SubstitutionSimplifierResult
    deriving (Show)
    deriving (GHC.Generic)

instance SOP.Generic DebugSubstitutionSimplifier

instance SOP.HasDatatypeInfo DebugSubstitutionSimplifier

instance Pretty DebugSubstitutionSimplifier where
    pretty WhileSimplifySubstitution = "Simplifying substitution"
    pretty SubstitutionSimplifierResult = "Non-\\bottom result"

instance Entry DebugSubstitutionSimplifier where
    entrySeverity _ = Debug
    shortDoc _ = Just "while simplifying substitution"
    helpDoc _ = "log non-\\bottom results when normalizing unification solutions"

instance SQL.Table DebugSubstitutionSimplifier

whileDebugSubstitutionSimplifier
    :: MonadLog log
    => log a
    -> log a
whileDebugSubstitutionSimplifier =
    logWhile WhileSimplifySubstitution

debugSubstitutionSimplifierResult
    :: MonadLog log
    => log ()
debugSubstitutionSimplifierResult = logEntry SubstitutionSimplifierResult

{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}

module Kore.Logger.WarnFunctionWithoutEvaluators
    ( WarnFunctionWithoutEvaluators (..)
    , warnFunctionWithoutEvaluators
    ) where

import Data.Text.Prettyprint.Doc
    ( Pretty
    )
import qualified Data.Text.Prettyprint.Doc as Pretty
import Data.Typeable
    ( Typeable
    )

import Kore.Internal.Symbol
    ( Symbol
    )
import Kore.Logger
    ( Entry (..)
    , MonadLog
    , Severity (Warning)
    , logM
    )
import Kore.Unparser
    ( unparse
    )

newtype WarnFunctionWithoutEvaluators = WarnFunctionWithoutEvaluators
    { symbol :: Symbol
    } deriving (Eq, Typeable)

instance Pretty WarnFunctionWithoutEvaluators where
    pretty WarnFunctionWithoutEvaluators { symbol } =
        Pretty.vsep
            [ "No evaluators for function symbol:"
            , Pretty.indent 4 (unparse symbol)
            ]

instance Entry WarnFunctionWithoutEvaluators where
    entrySeverity _ = Warning

warnFunctionWithoutEvaluators :: MonadLog m => Symbol -> m ()
warnFunctionWithoutEvaluators symbol =
    logM WarnFunctionWithoutEvaluators { symbol }

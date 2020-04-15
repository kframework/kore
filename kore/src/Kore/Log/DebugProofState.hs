{- |
Copyright   : (c) Runtime Verification, 2020
License     : NCSA
-}

module Kore.Log.DebugProofState
    ( DebugProofState (..)
    ) where

import Prelude.Kore

import Data.Text.Prettyprint.Doc
    ( Pretty (..)
    )
import qualified Data.Text.Prettyprint.Doc as Pretty

import Kore.Internal.TermLike
    ( Variable
    )
import Kore.Step.RulePattern
    ( ReachabilityRule (..)
    , RewriteRule (..)
    )
import Kore.Strategies.ProofState
    ( Prim (..)
    , ProofState (..)
    )
import Log

data DebugProofState =
    DebugProofState
        { proofState :: ProofState (ReachabilityRule Variable)
        , transition :: Prim (RewriteRule Variable)
        , result :: Maybe (ProofState (ReachabilityRule Variable))
        }

instance Pretty DebugProofState where
    pretty
        DebugProofState
            { proofState
            , transition
            , result
            }
      =
        Pretty.vsep
            [ "Reached proof state with the following configuration:"
            , Pretty.indent 4 (pretty proofState)
            , "On which the following transition applies:"
            , Pretty.indent 4 (prettyTransition transition)
            , "Resulting in:"
            , Pretty.indent 4 (maybe "Terminal state." pretty result)
            ]
      where
        prettyTransition (DeriveSeq _) = "Transition DeriveSeq."
        prettyTransition (DerivePar _) = "Transition DerivePar."
        prettyTransition prim          = Pretty.pretty prim

instance Entry DebugProofState where
    entrySeverity _ = Debug

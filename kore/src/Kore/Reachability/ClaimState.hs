{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
-}
module Kore.Reachability.ClaimState
    ( extractRemaining
    , extractUnproven
    , extractStuck
    , retractRewritable, isRewritable
    , ClaimState (..)
    , claimState
    , ClaimStateTransformer (..)
    ) where

import Prelude.Kore

import Control.DeepSeq
    ( NFData
    )
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Debug
import Kore.Unparser
    ( Unparse (..)
    )
import Pretty
    ( Pretty (..)
    )
import qualified Pretty

{- | The state of the reachability proof strategy for @claim@.
 -}
data ClaimState claim
    = Claimed !claim
    -- ^ The claim is being proven.
    | Remaining !claim
    -- ^ The claim is being rewritten, but no rule has applied.
    | Rewritten !claim
    -- ^ The claim was rewritten.
    | Stuck !claim
    -- ^ The proof of this claim cannot be completed because the implication
    -- does not hold.
    | Proven
    -- ^ The claim was proven.
    deriving (Eq, Show, Ord)
    deriving (Foldable, Functor)
    deriving (GHC.Generic)

instance NFData claim => NFData (ClaimState claim)

instance Hashable claim => Hashable (ClaimState claim)

instance SOP.Generic (ClaimState a)

instance SOP.HasDatatypeInfo (ClaimState a)

instance Debug a => Debug (ClaimState a)

instance (Debug a, Diff a) => Diff (ClaimState a)

instance Unparse claim => Pretty (ClaimState claim) where
    pretty (Claimed claim) =
        Pretty.vsep
            [ "claimed:"
            , Pretty.indent 4 $ unparse claim
            ]
    pretty (Remaining claim) =
        Pretty.vsep
            [ "remaining:"
            , Pretty.indent 4 $ unparse claim
            ]
    pretty (Rewritten claim) =
        Pretty.vsep
            [ "rewritten:"
            , Pretty.indent 4 $ unparse claim
            ]
    pretty (Stuck claim) =
        Pretty.vsep
            [ "stuck:"
            , Pretty.indent 4 $ unparse claim
            ]
    pretty Proven = "proven"

{- | Extract the unproven claims of a 'ClaimState'.

Returns 'Nothing' if there is no remaining unproven claim.

 -}
extractUnproven :: ClaimState a -> Maybe a
extractUnproven (Claimed t)   = Just t
extractUnproven (Rewritten t) = Just t
extractUnproven (Remaining t) = Just t
extractUnproven (Stuck t)     = Just t
extractUnproven Proven        = Nothing

extractRemaining :: ClaimState a -> Maybe a
extractRemaining (Remaining t) = Just t
extractRemaining _             = Nothing

extractStuck :: ClaimState a -> Maybe a
extractStuck (Stuck a) = Just a
extractStuck _         = Nothing

retractRewritable :: ClaimState a -> Maybe a
retractRewritable (Claimed a)   = Just a
retractRewritable (Remaining a) = Just a
retractRewritable _             = Nothing

isRewritable :: ClaimState a -> Bool
isRewritable = isJust . retractRewritable

data ClaimStateTransformer a val =
    ClaimStateTransformer
        { claimedTransformer :: a -> val
        , remainingTransformer :: a -> val
        , rewrittenTransformer :: a -> val
        , stuckTransformer :: a -> val
        , provenValue :: val
        }

{- | Catamorphism for 'ClaimState'
-}
claimState
    :: ClaimStateTransformer a val
    -> ClaimState a
    -> val
claimState
    ClaimStateTransformer
        { claimedTransformer
        , remainingTransformer
        , rewrittenTransformer
        , stuckTransformer
        , provenValue
        }
  =
    \case
        Claimed claim -> claimedTransformer claim
        Remaining claim -> remainingTransformer claim
        Rewritten claim -> rewrittenTransformer claim
        Stuck claim -> stuckTransformer claim
        Proven -> provenValue

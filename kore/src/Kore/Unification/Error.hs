{-|
Module      : Kore.Unification.Error
Description : Utilities for unification errors
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Unification.Error
    ( SubstitutionError (..)
    , UnificationError (..)
    , UnificationOrSubstitutionError (..)
    , errorIfConcreteIncompletelyUnified
    , substitutionToUnifyOrSubError
    , unificationToUnifyOrSubError
    ) where

import qualified Control.Monad as Monad
import           Data.Text.Prettyprint.Doc
                 ( Pretty )
import qualified Data.Text.Prettyprint.Doc as Pretty
import           GHC.Stack
                 ( HasCallStack )

import           Kore.Internal.Pattern
                 ( Pattern )
import qualified Kore.Internal.Pattern as Pattern
                 ( Conditional (..) )
import           Kore.Internal.TermLike
                 ( TermLike )
import           Kore.Sort
import           Kore.Syntax.Application
import           Kore.Syntax.Variable
import           Kore.Unparser

-- | Hack sum-type to wrap unification and substitution errors
data UnificationOrSubstitutionError
    = UnificationError UnificationError
    | SubstitutionError SubstitutionError
    deriving Show

instance Pretty UnificationOrSubstitutionError where
    pretty (UnificationError  err) = Pretty.pretty err
    pretty (SubstitutionError err) = Pretty.pretty err

-- |'UnificationError' specifies various error cases encountered during
-- unification
data UnificationError = UnsupportedPatterns
    deriving (Eq, Show)

instance Pretty UnificationError where
    pretty UnsupportedPatterns = "Unsupported patterns"

-- |@ClashReason@ describes the head of a pattern involved in a clash.
data ClashReason
    = HeadClash SymbolOrAlias
    | DomainValueClash String
    | SortInjectionClash Sort Sort
    deriving (Eq, Show)

{-| 'SubstitutionError' specifies the various error cases related to
substitutions.
-}
data SubstitutionError =
    forall variable.
    (Ord variable, Show variable, SortedVariable variable, Unparse variable) =>
    NonCtorCircularVariableDependency [variable]
    -- ^ the circularity path may pass through non-constructors: maybe solvable.

instance Show SubstitutionError where
    showsPrec prec (NonCtorCircularVariableDependency variables) =
        showParen (prec >= 10)
        $ showString "NonCtorCircularVariableDependency "
        . showList variables

instance Pretty SubstitutionError where
    pretty (NonCtorCircularVariableDependency vars) =
        Pretty.vsep
        ( "Non-constructor circular variable dependency:"
        : (unparse <$> vars)
        )

-- Trivially promote substitution errors to sum-type errors
substitutionToUnifyOrSubError
    :: SubstitutionError
    -> UnificationOrSubstitutionError
substitutionToUnifyOrSubError = SubstitutionError

-- Trivially promote unification errors to sum-type errors
unificationToUnifyOrSubError
    :: UnificationError
    -> UnificationOrSubstitutionError
unificationToUnifyOrSubError = UnificationError

-- Setup: we are unifying against a concrete (no variables) pattern
-- If the unification problem is completely solved, we expect that
-- the term of the unifier is precisely the concrete pattern.
-- If not, this is probably because the term contains an and coming from
-- an incomplete unification problem.
-- An example of how this might happen is unifying a concrete pattern
-- against a non-functional term.
-- Since this case is not yet handled by the unification algorithm
-- we choose to throw an error here.
errorIfConcreteIncompletelyUnified
    ::  ( Monad m
        , Ord variable
        , Show variable
        , SortedVariable variable
        , Unparse variable
        , HasCallStack
        )
    => TermLike variable
    -> TermLike variable
    -> Pattern variable
    -> m ()
errorIfConcreteIncompletelyUnified expected patt unifiedPattern =
    Monad.when (Pattern.term unifiedPattern /= expected)
        $ error
            (  "Unification problem not completely solved. "
            ++ "When unfying against concrete pattern\n\t"
            ++ show (unparseToString expected)
            ++ "\nwith pattern\n\t"
            ++ show (unparseToString patt)
            ++ "\nExpecting to get the concrete pattern back but got\n\t"
            ++ show (unparseToString unifiedPattern)
            ++ "\nHandling this is currently not implemented."
            ++ "\nPlease file an issue if this should work for you."
            )

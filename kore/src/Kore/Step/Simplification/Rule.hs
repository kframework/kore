{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
-}
module Kore.Step.Simplification.Rule
    ( simplifyRulePattern
    , simplifyRewriteRule
    , simplifyEqualityRule
    , simplifyFunctionAxioms
    ) where

import Data.Map
       ( Map )

import           Kore.Internal.Conditional
                 ( Conditional (..) )
import           Kore.Internal.OrPattern
                 ( OrPattern )
import qualified Kore.Internal.OrPattern as OrPattern
import qualified Kore.Internal.Pattern as Pattern
import           Kore.Internal.TermLike
                 ( TermLike )
import qualified Kore.Internal.TermLike as TermLike
import           Kore.Predicate.Predicate
                 ( pattern PredicateTrue )
import           Kore.Step.Rule
import           Kore.Step.Simplification.Data
                 ( Simplifier )
import qualified Kore.Step.Simplification.Data as Simplifier
import qualified Kore.Step.Simplification.Pattern as Pattern
import qualified Kore.Step.Simplification.Predicate as Predicate
import qualified Kore.Step.Simplification.Simplifier as Simplifier
import qualified Kore.Unification.Substitution as Substitution
import           Kore.Unparser
                 ( Unparse )
import           Kore.Variables.Fresh

{- | Simplify a 'Map' of 'EqualityRule's using only matching logic rules.

See also: 'simplifyRulePattern'

 -}
simplifyFunctionAxioms
    ::  ( FreshVariable variable
        , SortedVariable variable
        , Show variable
        , Unparse variable
        )
    =>  Map identifier [EqualityRule variable]
    ->  Simplifier (Map identifier [EqualityRule variable])
simplifyFunctionAxioms =
    (traverse . traverse) simplifyEqualityRule

simplifyEqualityRule
    ::  ( FreshVariable variable
        , SortedVariable variable
        , Show variable
        , Unparse variable
        )
    =>  EqualityRule variable
    ->  Simplifier (EqualityRule variable)
simplifyEqualityRule (EqualityRule rule) =
    EqualityRule <$> simplifyRulePattern rule

{- | Simplify a 'Rule' using only matching logic rules.

See also: 'simplifyRulePattern'

 -}
simplifyRewriteRule
    ::  ( FreshVariable variable
        , SortedVariable variable
        , Show variable
        , Unparse variable
        )
    =>  RewriteRule variable
    ->  Simplifier (RewriteRule variable)
simplifyRewriteRule (RewriteRule rule) =
    RewriteRule <$> simplifyRulePattern rule

{- | Simplify a 'RulePattern' using only matching logic rules.

The original rule is returned unless the simplification result matches certain
narrowly-defined criteria.

 -}
simplifyRulePattern
    ::  ( FreshVariable variable
        , SortedVariable variable
        , Show variable
        , Unparse variable
        )
    =>  RulePattern variable
    ->  Simplifier (RulePattern variable)
simplifyRulePattern rule = do
    let RulePattern { left } = rule
    simplifiedLeft <- simplifyPattern left
    case OrPattern.toPatterns simplifiedLeft of
        [ Conditional { term, predicate, substitution } ]
          | PredicateTrue <- predicate -> do
            let subst = Substitution.toMap substitution
                left' = TermLike.substitute subst term
                right' = TermLike.substitute subst right
                  where
                    RulePattern { right } = rule
                requires' = TermLike.substitute subst <$> requires
                  where
                    RulePattern { requires } = rule
                ensures' = TermLike.substitute subst <$> ensures
                  where
                    RulePattern { ensures } = rule
                RulePattern { attributes } = rule
            return RulePattern
                { left = left'
                , right = right'
                , requires = requires'
                , ensures = ensures'
                , attributes = attributes
                }
        _ ->
            -- Unable to simplify the given rule pattern, so we return the
            -- original pattern in the hope that we can do something with it
            -- later.
            return rule

-- | Simplify a 'TermLike' using only matching logic rules.
simplifyPattern
    ::  ( FreshVariable variable
        , SortedVariable variable
        , Show variable
        , Unparse variable
        )
    =>  TermLike variable
    ->  Simplifier (OrPattern variable)
simplifyPattern termLike =
    Simplifier.localSimplifierTermLike (const Simplifier.create)
    $ Simplifier.localSimplifierPredicate (const Predicate.create)
    $ Simplifier.localSimplifierAxioms (const mempty)
    $ Pattern.simplify (Pattern.fromTermLike termLike)

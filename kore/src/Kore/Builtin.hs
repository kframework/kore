{- |
Module      : Kore.Builtin
Description : Built-in sorts and symbols
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : thomas.tuegel@runtimeverification.com
Stability   : experimental
Portability : portable

This module is intended to be imported qualified.

@
    import qualified Kore.Builtin as Builtin
@
 -}
module Kore.Builtin
    ( Builtin.Verifiers (..)
    , Builtin.DomainValueVerifiers
    , Builtin.Function
    , Builtin
    , Builtin.SymbolVerifier (..)
    , Builtin.SortVerifier (..)
    , Builtin.sortDeclVerifier
    , Builtin.symbolVerifier
    , Builtin.verifyDomainValue
    , koreVerifiers
    , koreEvaluators
    , evaluators
    , externalizePattern
    , externalizePattern'
    ) where

import qualified Data.Functor.Foldable as Recursive
import qualified Data.HashMap.Strict as HashMap
import           Data.Map
                 ( Map )
import qualified Data.Map as Map
import           Data.Semigroup
                 ( (<>) )
import           Data.Text
                 ( Text )
import qualified GHC.Stack as GHC

import qualified Kore.Attribute.Axiom as Attribute
import           Kore.Attribute.Hook
                 ( Hook (..) )
import qualified Kore.Attribute.Null as Attribute
import           Kore.Attribute.Symbol
                 ( StepperAttributes )
import qualified Kore.Attribute.Symbol as Attribute
import qualified Kore.Builtin.Bool as Bool
import qualified Kore.Builtin.Builtin as Builtin
import qualified Kore.Builtin.Int as Int
import qualified Kore.Builtin.KEqual as KEqual
import qualified Kore.Builtin.Krypto as Krypto
import qualified Kore.Builtin.List as List
import qualified Kore.Builtin.Map as Map
import qualified Kore.Builtin.Set as Set
import qualified Kore.Builtin.String as String
import qualified Kore.Domain.Builtin as Domain
import           Kore.IndexedModule.IndexedModule
                 ( IndexedModule (..), VerifiedModule )
import qualified Kore.IndexedModule.IndexedModule as IndexedModule
import           Kore.Internal.TermLike
import           Kore.Step.Axiom.Identifier
                 ( AxiomIdentifier )
import qualified Kore.Step.Axiom.Identifier as AxiomIdentifier
                 ( AxiomIdentifier (..) )
import qualified Kore.Syntax.Pattern as Syntax

{- | Verifiers for Kore builtin sorts.

  If you aren't sure which verifiers you need, use these.

 -}
koreVerifiers :: Builtin.Verifiers
koreVerifiers =
    Builtin.Verifiers
    { sortDeclVerifiers =
           Bool.sortDeclVerifiers
        <> Int.sortDeclVerifiers
        <> List.sortDeclVerifiers
        <> Map.sortDeclVerifiers
        <> Set.sortDeclVerifiers
        <> String.sortDeclVerifiers
    , symbolVerifiers =
           Bool.symbolVerifiers
        <> Int.symbolVerifiers
        <> List.symbolVerifiers
        <> Map.symbolVerifiers
        <> KEqual.symbolVerifiers
        <> Set.symbolVerifiers
        <> String.symbolVerifiers
        <> Krypto.symbolVerifiers
    , domainValueVerifiers =
        HashMap.fromList
            [ (Bool.sort, Bool.patternVerifier)
            , (Int.sort, Int.patternVerifier)
            , (String.sort, String.patternVerifier)
            ]
    }

{- | Construct an evaluation context for Kore builtin functions.

  Returns a map from symbol identifiers to builtin functions used for function
  evaluation in the context of the given module.

  See also: 'Data.Step.Step.step'

 -}
koreEvaluators
    :: VerifiedModule StepperAttributes Attribute.Axiom
    -- ^ Module under which evaluation takes place
    -> Map (AxiomIdentifier) Builtin.Function
koreEvaluators = evaluators builtins
  where
    builtins :: Map Text Builtin.Function
    builtins =
        Map.unions
            [ Bool.builtinFunctions
            , Int.builtinFunctions
            , KEqual.builtinFunctions
            , List.builtinFunctions
            , Map.builtinFunctions
            , Set.builtinFunctions
            , String.builtinFunctions
            , Krypto.builtinFunctions
            ]

{- | Construct an evaluation context for the given builtin functions.

  Returns a map from symbol identifiers to builtin functions used for function
  evaluation in the context of the given module.

  See also: 'Data.Step.Step.step', 'koreEvaluators'

 -}
evaluators
    :: Map Text Builtin.Function
    -- ^ Builtin functions indexed by name
    -> VerifiedModule StepperAttributes Attribute.Axiom
    -- ^ Module under which evaluation takes place
    -> Map (AxiomIdentifier) Builtin.Function
evaluators builtins indexedModule =
    Map.mapMaybe
        lookupBuiltins
        (Map.mapKeys
            AxiomIdentifier.Application
            (hookedSymbolAttributes indexedModule)
        )
  where
    hookedSymbolAttributes
        :: VerifiedModule StepperAttributes Attribute.Axiom
        -> Map Id StepperAttributes
    hookedSymbolAttributes im =
        Map.union
            (justAttributes <$> IndexedModule.hookedObjectSymbolSentences im)
            (Map.unions
                (importHookedSymbolAttributes <$> indexedModuleImports im)
            )
      where
        justAttributes (attrs, _) = attrs

    importHookedSymbolAttributes
        :: (a, b, VerifiedModule StepperAttributes Attribute.Axiom)
        -> Map Id StepperAttributes
    importHookedSymbolAttributes (_, _, im) = hookedSymbolAttributes im

    lookupBuiltins :: StepperAttributes -> Maybe Builtin.Function
    lookupBuiltins Attribute.Symbol { Attribute.hook = Hook { getHook } } =
        do
            name <- getHook
            impl <- Map.lookup name builtins
            pure impl

{- | Externalize all builtin domain values in the given pattern.

All builtins will be rendered using their concrete Kore syntax.

See also: 'asPattern'

 -}
-- TODO (thomas.tuegel): Transform from Domain.Internal to Domain.External.
externalizePattern
    ::  forall variable. Ord variable
    =>  TermLike variable
    ->  TermLike variable
externalizePattern =
    Recursive.unfold externalizePatternWorker
  where
    externalizePatternWorker
        ::  TermLike variable
        ->  Recursive.Base (TermLike variable) (TermLike variable)
    externalizePatternWorker (Recursive.project -> original@(_ :< pat)) =
        case pat of
            BuiltinF domain ->
                case domain of
                    Domain.BuiltinExternal _ -> original
                    Domain.BuiltinMap  builtin ->
                        Recursive.project (Map.asTermLike builtin)
                    Domain.BuiltinList builtin ->
                        Recursive.project (List.asTermLike builtin)
                    Domain.BuiltinSet  builtin ->
                        Recursive.project (Set.asTermLike builtin)
                    Domain.BuiltinInt  builtin ->
                        Recursive.project (Int.asTermLike builtin)
                    Domain.BuiltinBool builtin ->
                        Recursive.project (Bool.asTermLike builtin)
                    Domain.BuiltinString builtin ->
                        Recursive.project (String.asTermLike builtin)
            _ -> original

{- | Externalize the 'TermLike' into a 'Syntax.Pattern'.

All builtins will be rendered using their concrete Kore syntax.

See also: 'asPattern'

 -}
externalizePattern'
    ::  forall variable. Ord variable
    =>  TermLike variable
    ->  Syntax.Pattern Domain.External variable Attribute.Null
externalizePattern' =
    Recursive.unfold externalizePatternWorker
  where
    externalizePatternWorker
        ::  TermLike variable
        ->  Recursive.Base
                (Syntax.Pattern Domain.External variable Attribute.Null)
                (TermLike variable)
    externalizePatternWorker termLike =
        case termLikeF of
            BuiltinF domain ->
                case domain of
                    Domain.BuiltinMap  builtin ->
                        (toPatternF . Recursive.project)
                            (Map.asTermLike builtin)
                    Domain.BuiltinList builtin ->
                        (toPatternF . Recursive.project)
                            (List.asTermLike builtin)
                    Domain.BuiltinSet  builtin ->
                        (toPatternF . Recursive.project)
                            (Set.asTermLike builtin)
                    Domain.BuiltinInt  builtin ->
                        (toPatternF . Recursive.project)
                            (Int.asTermLike builtin)
                    Domain.BuiltinBool builtin ->
                        (toPatternF . Recursive.project)
                            (Bool.asTermLike builtin)
                    Domain.BuiltinString builtin ->
                        (toPatternF . Recursive.project)
                            (String.asTermLike builtin)
                    Domain.BuiltinExternal external ->
                        Attribute.Null :< Syntax.DomainValueF external
            _ -> toPatternF termLikeBase
      where
        termLikeBase@(_ :< termLikeF) = Recursive.project termLike

    toPatternF
        :: GHC.HasCallStack
        => Recursive.Base (TermLike variable) child
        -> Recursive.Base
            (Syntax.Pattern Domain.External variable Attribute.Null)
            child
    toPatternF (_ :< termLikeF) =
        (Attribute.Null :<)
        $ case termLikeF of
            AndF andF -> Syntax.AndF andF
            ApplicationF applicationF -> Syntax.ApplicationF applicationF
            BottomF bottomF -> Syntax.BottomF bottomF
            CeilF ceilF -> Syntax.CeilF ceilF
            DomainValueF domainValueF -> Syntax.DomainValueF domainValueF
            EqualsF equalsF -> Syntax.EqualsF equalsF
            ExistsF existsF -> Syntax.ExistsF existsF
            FloorF floorF -> Syntax.FloorF floorF
            ForallF forallF -> Syntax.ForallF forallF
            IffF iffF -> Syntax.IffF iffF
            ImpliesF impliesF -> Syntax.ImpliesF impliesF
            InF inF -> Syntax.InF inF
            NextF nextF -> Syntax.NextF nextF
            NotF notF -> Syntax.NotF notF
            OrF orF -> Syntax.OrF orF
            RewritesF rewritesF -> Syntax.RewritesF rewritesF
            StringLiteralF stringLiteralF -> Syntax.StringLiteralF stringLiteralF
            CharLiteralF charLiteralF -> Syntax.CharLiteralF charLiteralF
            TopF topF -> Syntax.TopF topF
            VariableF variableF -> Syntax.VariableF variableF
            InhabitantF inhabitantF -> Syntax.InhabitantF inhabitantF
            SetVariableF setVariableF -> Syntax.SetVariableF setVariableF
            BuiltinF _ -> error "Unexpected internal builtin"

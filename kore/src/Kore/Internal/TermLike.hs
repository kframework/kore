{-|
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.Internal.TermLike
    ( TermLikeF (..)
    , TermLike (..)
    , Evaluated (..)
    , Builtin
    , extractAttributes
    , freeVariables
    , termLikeSort
    , hasFreeVariable
    , withoutFreeVariable
    , mapVariables
    , traverseVariables
    , asConcrete
    , isConcrete
    , fromConcrete
    , substitute
    , externalizeFreshVariables
    -- * Utility functions for dealing with sorts
    , forceSort
    -- * Pure Kore pattern constructors
    , mkAnd
    , mkApplyAlias
    , mkApplySymbol
    , mkBottom
    , mkBuiltin
    , mkCeil
    , mkDomainValue
    , mkEquals
    , mkExists
    , mkFloor
    , mkForall
    , mkIff
    , mkImplies
    , mkIn
    , mkMu
    , mkNext
    , mkNot
    , mkNu
    , mkOr
    , mkRewrites
    , mkTop
    , mkVar
    , mkSetVar
    , mkStringLiteral
    , mkCharLiteral
    , mkSort
    , mkSortVariable
    , mkInhabitant
    , mkEvaluated
    , varS
    -- * Predicate constructors
    , mkBottom_
    , mkCeil_
    , mkEquals_
    , mkFloor_
    , mkIn_
    , mkTop_
    -- * Sentence constructors
    , mkAlias
    , mkAlias_
    , mkAxiom
    , mkAxiom_
    , mkSymbol
    , mkSymbol_
    -- * Application constructors
    , applyAlias
    , applyAlias_
    , applySymbol
    , applySymbol_
    -- * Pattern synonyms
    , pattern And_
    , pattern ApplyAlias_
    , pattern App_
    , pattern Bottom_
    , pattern Builtin_
    , pattern Ceil_
    , pattern DV_
    , pattern Equals_
    , pattern Exists_
    , pattern Floor_
    , pattern Forall_
    , pattern Iff_
    , pattern Implies_
    , pattern In_
    , pattern Next_
    , pattern Not_
    , pattern Or_
    , pattern Rewrites_
    , pattern Top_
    , pattern Var_
    , pattern V
    , pattern StringLiteral_
    , pattern CharLiteral_
    , pattern Evaluated_
    -- * Re-exports
    , Symbol (..)
    , Alias (..)
    , SortedVariable (..)
    , module Kore.Syntax.Id
    , CofreeF (..), Comonad (..)
    , Sort (..), SortActual (..), SortVariable (..)
    , charMetaSort, stringMetaSort
    , module Kore.Syntax.And
    , module Kore.Syntax.Application
    , module Kore.Syntax.Bottom
    , module Kore.Syntax.Ceil
    , module Kore.Syntax.CharLiteral
    , module Kore.Syntax.DomainValue
    , module Kore.Syntax.Equals
    , module Kore.Syntax.Exists
    , module Kore.Syntax.Floor
    , module Kore.Syntax.Forall
    , module Kore.Syntax.Iff
    , module Kore.Syntax.Implies
    , module Kore.Syntax.In
    , module Kore.Syntax.Mu
    , module Kore.Syntax.Next
    , module Kore.Syntax.Not
    , module Kore.Syntax.Nu
    , module Kore.Syntax.Or
    , module Kore.Syntax.Rewrites
    , module Kore.Syntax.SetVariable
    , module Kore.Syntax.StringLiteral
    , module Kore.Syntax.Top
    , module Variable
    ) where


import           Control.Applicative
import           Control.Comonad
import           Control.Comonad.Trans.Cofree
import qualified Control.Comonad.Trans.Env as Env
import           Control.DeepSeq
                 ( NFData (..) )
import qualified Control.Lens as Lens
import           Control.Monad.Reader
                 ( Reader )
import qualified Control.Monad.Reader as Reader
import           Data.Align
import qualified Data.Bifunctor as Bifunctor
import qualified Data.Default as Default
import qualified Data.Deriving as Deriving
import qualified Data.Foldable as Foldable
import           Data.Function
import           Data.Functor.Classes
import           Data.Functor.Compose
                 ( Compose (..) )
import           Data.Functor.Foldable
                 ( Base, Corecursive, Recursive )
import qualified Data.Functor.Foldable as Recursive
import           Data.Functor.Identity
                 ( Identity (..) )
import           Data.Hashable
import           Data.Map.Strict
                 ( Map )
import qualified Data.Map.Strict as Map
import           Data.Maybe
import qualified Data.Set as Set
import           Data.Text
                 ( Text )
import qualified Data.Text.Prettyprint.Doc as Pretty
import           Data.These
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC
import qualified GHC.Stack as GHC

import qualified Kore.Attribute.Pattern as Attribute
import           Kore.Attribute.Pattern.FreeVariables
                 ( FreeVariables )
import qualified Kore.Attribute.Pattern.FreeVariables as FreeVariables
import qualified Kore.Attribute.Pattern.Function as Pattern
import qualified Kore.Attribute.Pattern.Functional as Pattern
import           Kore.Attribute.Synthetic
import qualified Kore.Domain.Builtin as Domain
import           Kore.Domain.Class
import           Kore.Error
import           Kore.Internal.Alias
import           Kore.Internal.Symbol
import           Kore.Sort
import qualified Kore.Substitute as Substitute
import           Kore.Syntax.And
import           Kore.Syntax.Application
import           Kore.Syntax.Bottom
import           Kore.Syntax.Ceil
import           Kore.Syntax.CharLiteral
import           Kore.Syntax.Definition hiding
                 ( Alias, Symbol )
import qualified Kore.Syntax.Definition as Syntax
import           Kore.Syntax.DomainValue
import           Kore.Syntax.Equals
import           Kore.Syntax.Exists
import           Kore.Syntax.Floor
import           Kore.Syntax.Forall
import           Kore.Syntax.Id
import           Kore.Syntax.Iff
import           Kore.Syntax.Implies
import           Kore.Syntax.In
import           Kore.Syntax.Mu
import           Kore.Syntax.Next
import           Kore.Syntax.Not
import           Kore.Syntax.Nu
import           Kore.Syntax.Or
import           Kore.Syntax.Rewrites
import           Kore.Syntax.SetVariable
import           Kore.Syntax.StringLiteral
import           Kore.Syntax.Top
import           Kore.Syntax.Variable as Variable
import           Kore.TopBottom
import           Kore.Unparser
                 ( Unparse (..) )
import qualified Kore.Unparser as Unparser
import           Kore.Variables.Binding
import           Kore.Variables.Fresh

{- | @Evaluated@ wraps patterns which are fully evaluated.

Fully-evaluated patterns will not be simplified further because no progress
could be made.

 -}
newtype Evaluated child = Evaluated { getEvaluated :: child }
    deriving (Eq, Foldable, Functor, GHC.Generic, Ord, Show, Traversable)

Deriving.deriveEq1 ''Evaluated
Deriving.deriveOrd1 ''Evaluated
Deriving.deriveShow1 ''Evaluated

instance SOP.Generic (Evaluated child)

instance SOP.HasDatatypeInfo (Evaluated child)

instance Hashable child => Hashable (Evaluated child)

instance NFData child => NFData (Evaluated child)

instance Unparse child => Unparse (Evaluated child) where
    unparse evaluated =
        Pretty.vsep ["/* evaluated: */", Unparser.unparseGeneric evaluated]
    unparse2 evaluated =
        Pretty.vsep ["/* evaluated: */", Unparser.unparse2Generic evaluated]

instance Synthetic Evaluated syn where
    synthetic = getEvaluated
    {-# INLINE synthetic #-}

-- | The type of internal domain values.
type Builtin = Domain.Builtin (TermLike Concrete)

{- | 'TermLikeF' is the 'Base' functor of internal term-like patterns.

-}
data TermLikeF variable child
    = AndF           !(And Sort child)
    | ApplySymbolF   !(Application Symbol child)
    | ApplyAliasF    !(Application Alias child)
    | BottomF        !(Bottom Sort child)
    | CeilF          !(Ceil Sort child)
    | DomainValueF   !(DomainValue Sort child)
    | EqualsF        !(Equals Sort child)
    | ExistsF        !(Exists Sort variable child)
    | FloorF         !(Floor Sort child)
    | ForallF        !(Forall Sort variable child)
    | IffF           !(Iff Sort child)
    | ImpliesF       !(Implies Sort child)
    | InF            !(In Sort child)
    | MuF            !(Mu variable child)
    | NextF          !(Next Sort child)
    | NotF           !(Not Sort child)
    | NuF            !(Nu variable child)
    | OrF            !(Or Sort child)
    | RewritesF      !(Rewrites Sort child)
    | StringLiteralF !StringLiteral
    | CharLiteralF   !CharLiteral
    | TopF           !(Top Sort child)
    | VariableF      !variable
    | InhabitantF    !Sort
    | SetVariableF   !(SetVariable variable)
    | BuiltinF       !(Builtin child)
    | EvaluatedF     !(Evaluated child)
    deriving (Foldable, Functor, GHC.Generic, Traversable)

instance (Eq variable, Eq child) => Eq (TermLikeF variable child) where
    (==) = eq1
    {-# INLINE (==) #-}

instance (Ord variable, Ord child) => Ord (TermLikeF variable child) where
    compare = compare1
    {-# INLINE compare #-}

instance (Show variable, Show child) => Show (TermLikeF variable child) where
    showsPrec = showsPrec1
    {-# INLINE showsPrec #-}

instance SOP.Generic (TermLikeF variable child)

instance SOP.HasDatatypeInfo (TermLikeF variable child)

instance
    (Hashable child, Hashable variable) =>
    Hashable (TermLikeF variable child)

instance (NFData child, NFData variable) => NFData (TermLikeF variable child)

instance
    ( SortedVariable variable, Unparse variable
    , Unparse child
    ) =>
    Unparse (TermLikeF variable child)
  where
    unparse = Unparser.unparseGeneric
    unparse2 = Unparser.unparse2Generic

instance
    Ord variable =>
    Synthetic (TermLikeF variable) (FreeVariables variable)
  where
    -- TODO (thomas.tuegel): Use SOP.Generic here, after making the children
    -- Functors.
    synthetic (ForallF forallF) = synthetic forallF
    synthetic (ExistsF existsF) = synthetic existsF
    synthetic (VariableF variable) = FreeVariables.singleton variable

    synthetic (AndF andF) = synthetic andF
    synthetic (ApplySymbolF applySymbolF) = synthetic applySymbolF
    synthetic (ApplyAliasF _) = undefined
    synthetic (BottomF bottomF) = synthetic bottomF
    synthetic (CeilF ceilF) = synthetic ceilF
    synthetic (DomainValueF domainValueF) = synthetic domainValueF
    synthetic (EqualsF equalsF) = synthetic equalsF
    synthetic (FloorF floorF) = synthetic floorF
    synthetic (IffF iffF) = synthetic iffF
    synthetic (ImpliesF impliesF) = synthetic impliesF
    synthetic (InF inF) = synthetic inF
    synthetic (NextF nextF) = synthetic nextF
    synthetic (NotF notF) = synthetic notF
    synthetic (OrF orF) = synthetic orF
    synthetic (RewritesF rewritesF) = synthetic rewritesF
    synthetic (TopF topF) = synthetic topF
    synthetic (BuiltinF builtinF) = Foldable.fold builtinF
    synthetic (EvaluatedF evaluatedF) = synthetic evaluatedF

    synthetic (StringLiteralF _) = mempty
    synthetic (CharLiteralF _) = mempty
    synthetic (InhabitantF _) = mempty

    -- TODO (thomas.tuegel): Track free set variables.
    synthetic (MuF muF) = synthetic muF
    synthetic (NuF nuF) = synthetic nuF
    synthetic (SetVariableF _) = mempty
    {-# INLINE synthetic #-}

instance SortedVariable variable => Synthetic (TermLikeF variable) Sort where
    -- TODO (thomas.tuegel): Use SOP.Generic here, after making the children
    -- Functors.
    synthetic (ForallF forallF) = synthetic forallF
    synthetic (ExistsF existsF) = synthetic existsF
    synthetic (VariableF variable) = sortedVariableSort variable

    synthetic (AndF andF) = synthetic andF
    synthetic (ApplySymbolF applySymbolF) = synthetic applySymbolF
    synthetic (ApplyAliasF applyAliasF) = synthetic applyAliasF
    synthetic (BottomF bottomF) = synthetic bottomF
    synthetic (CeilF ceilF) = synthetic ceilF
    synthetic (DomainValueF domainValueF) = synthetic domainValueF
    synthetic (EqualsF equalsF) = synthetic equalsF
    synthetic (FloorF floorF) = synthetic floorF
    synthetic (IffF iffF) = synthetic iffF
    synthetic (ImpliesF impliesF) = synthetic impliesF
    synthetic (InF inF) = synthetic inF
    synthetic (NextF nextF) = synthetic nextF
    synthetic (NotF notF) = synthetic notF
    synthetic (OrF orF) = synthetic orF
    synthetic (RewritesF rewritesF) = synthetic rewritesF
    synthetic (TopF topF) = synthetic topF
    synthetic (BuiltinF builtinF) = synthetic builtinF
    synthetic (EvaluatedF evaluatedF) = synthetic evaluatedF

    synthetic (StringLiteralF _) = stringMetaSort
    synthetic (CharLiteralF _) = charMetaSort
    synthetic (InhabitantF inhSort) = inhSort

    synthetic (MuF muF) = synthetic muF
    synthetic (NuF nuF) = synthetic nuF
    synthetic (SetVariableF setVariable) =
        sortedVariableSort (getVariable setVariable)
    {-# INLINE synthetic #-}

instance Synthetic (TermLikeF variable) Pattern.Functional where
    -- TODO (thomas.tuegel): Use SOP.Generic here, after making the children
    -- Functors.
    synthetic (ForallF forallF) = synthetic forallF
    synthetic (ExistsF existsF) = synthetic existsF
    synthetic (VariableF _) = Pattern.Functional True

    synthetic (AndF andF) = synthetic andF
    synthetic (ApplySymbolF applySymbolF) = synthetic applySymbolF
    synthetic (ApplyAliasF applyAliasF) = synthetic applyAliasF
    synthetic (BottomF bottomF) = synthetic bottomF
    synthetic (CeilF ceilF) = synthetic ceilF
    synthetic (DomainValueF domainValueF) = synthetic domainValueF
    synthetic (EqualsF equalsF) = synthetic equalsF
    synthetic (FloorF floorF) = synthetic floorF
    synthetic (IffF iffF) = synthetic iffF
    synthetic (ImpliesF impliesF) = synthetic impliesF
    synthetic (InF inF) = synthetic inF
    synthetic (NextF nextF) = synthetic nextF
    synthetic (NotF notF) = synthetic notF
    synthetic (OrF orF) = synthetic orF
    synthetic (RewritesF rewritesF) = synthetic rewritesF
    synthetic (TopF topF) = synthetic topF
    synthetic (BuiltinF builtinF) = synthetic builtinF
    synthetic (EvaluatedF evaluatedF) = synthetic evaluatedF

    synthetic (StringLiteralF _) = Pattern.Functional True
    synthetic (CharLiteralF _) = Pattern.Functional True
    synthetic (InhabitantF _) = Pattern.Functional False

    synthetic (MuF muF) = synthetic muF
    synthetic (NuF nuF) = synthetic nuF
    synthetic (SetVariableF _) = Pattern.Functional False
    {-# INLINE synthetic #-}

instance Synthetic (TermLikeF variable) Pattern.Function where
    -- TODO (thomas.tuegel): Use SOP.Generic here, after making the children
    -- Functors.
    synthetic (ForallF forallF) = synthetic forallF
    synthetic (ExistsF existsF) = synthetic existsF
    synthetic (VariableF _) = Pattern.Function True

    synthetic (AndF andF) = synthetic andF
    synthetic (ApplySymbolF applySymbolF) = synthetic applySymbolF
    synthetic (ApplyAliasF applyAliasF) = synthetic applyAliasF
    synthetic (BottomF bottomF) = synthetic bottomF
    synthetic (CeilF ceilF) = synthetic ceilF
    synthetic (DomainValueF domainValueF) = synthetic domainValueF
    synthetic (EqualsF equalsF) = synthetic equalsF
    synthetic (FloorF floorF) = synthetic floorF
    synthetic (IffF iffF) = synthetic iffF
    synthetic (ImpliesF impliesF) = synthetic impliesF
    synthetic (InF inF) = synthetic inF
    synthetic (NextF nextF) = synthetic nextF
    synthetic (NotF notF) = synthetic notF
    synthetic (OrF orF) = synthetic orF
    synthetic (RewritesF rewritesF) = synthetic rewritesF
    synthetic (TopF topF) = synthetic topF
    synthetic (BuiltinF builtinF) = synthetic builtinF
    synthetic (EvaluatedF evaluatedF) = synthetic evaluatedF

    synthetic (StringLiteralF _) = Pattern.Function True
    synthetic (CharLiteralF _) = Pattern.Function True
    synthetic (InhabitantF _) = Pattern.Function False

    synthetic (MuF muF) = synthetic muF
    synthetic (NuF nuF) = synthetic nuF
    synthetic (SetVariableF _) = Pattern.Function False
    {-# INLINE synthetic #-}

{- | Use the provided mapping to replace all variables in a 'TermLikeF' head.

__Warning__: @mapVariablesF@ will capture variables if the provided mapping is
not injective!

-}
mapVariablesF
    :: (variable1 -> variable2)
    -> TermLikeF variable1 child
    -> TermLikeF variable2 child
mapVariablesF mapping = runIdentity . traverseVariablesF (Identity . mapping)

{- | Use the provided traversal to replace all variables in a 'TermLikeF' head.

__Warning__: @traverseVariablesF@ will capture variables if the provided
traversal is not injective!

-}
traverseVariablesF
    :: Applicative f
    => (variable1 -> f variable2)
    ->    TermLikeF variable1 child
    -> f (TermLikeF variable2 child)
traverseVariablesF traversing =
    \case
        -- Non-trivial cases
        ExistsF any0 -> ExistsF <$> traverseVariablesExists any0
        ForallF all0 -> ForallF <$> traverseVariablesForall all0
        MuF any0 -> MuF <$> traverseVariablesMu any0
        NuF any0 -> NuF <$> traverseVariablesNu any0
        VariableF variable -> VariableF <$> traversing variable
        SetVariableF (SetVariable variable) ->
            SetVariableF . SetVariable <$> traversing variable
        -- Trivial cases
        AndF andP -> pure (AndF andP)
        ApplySymbolF applySymbolF -> pure (ApplySymbolF applySymbolF)
        ApplyAliasF applyAliasF -> pure (ApplyAliasF applyAliasF)
        BottomF botP -> pure (BottomF botP)
        BuiltinF builtinP -> pure (BuiltinF builtinP)
        CeilF ceilP -> pure (CeilF ceilP)
        DomainValueF dvP -> pure (DomainValueF dvP)
        EqualsF eqP -> pure (EqualsF eqP)
        FloorF flrP -> pure (FloorF flrP)
        IffF iffP -> pure (IffF iffP)
        ImpliesF impP -> pure (ImpliesF impP)
        InF inP -> pure (InF inP)
        NextF nxtP -> pure (NextF nxtP)
        NotF notP -> pure (NotF notP)
        OrF orP -> pure (OrF orP)
        RewritesF rewP -> pure (RewritesF rewP)
        StringLiteralF strP -> pure (StringLiteralF strP)
        CharLiteralF charP -> pure (CharLiteralF charP)
        TopF topP -> pure (TopF topP)
        InhabitantF s -> pure (InhabitantF s)
        EvaluatedF childP -> pure (EvaluatedF childP)
  where
    traverseVariablesExists Exists { existsSort, existsVariable, existsChild } =
        Exists existsSort <$> traversing existsVariable <*> pure existsChild
    traverseVariablesForall Forall { forallSort, forallVariable, forallChild } =
        Forall forallSort <$> traversing forallVariable <*> pure forallChild
    traverseVariablesMu Mu { muVariable = SetVariable v, muChild } =
        Mu <$> (SetVariable <$> traversing v) <*> pure muChild
    traverseVariablesNu Nu { nuVariable = SetVariable v, nuChild } =
        Nu <$> (SetVariable <$> traversing v) <*> pure nuChild

newtype TermLike variable =
    TermLike
        { getTermLike
            :: Cofree (TermLikeF variable) (Attribute.Pattern variable)
        }
    deriving (GHC.Generic, Show)

Deriving.deriveEq1 ''TermLikeF
Deriving.deriveOrd1 ''TermLikeF
Deriving.deriveShow1 ''TermLikeF

instance Eq variable => Eq (TermLike variable) where
    (==) = eqWorker
      where
        eqWorker
            (Recursive.project -> _ :< pat1)
            (Recursive.project -> _ :< pat2)
          =
            liftEq eqWorker pat1 pat2
    {-# INLINE (==) #-}

instance Ord variable => Ord (TermLike variable) where
    compare = compareWorker
      where
        compareWorker
            (Recursive.project -> _ :< pat1)
            (Recursive.project -> _ :< pat2)
          =
            liftCompare compareWorker pat1 pat2
    {-# INLINE compare #-}

instance Hashable variable => Hashable (TermLike variable) where
    hashWithSalt salt (Recursive.project -> _ :< pat) = hashWithSalt salt pat
    {-# INLINE hashWithSalt #-}

instance NFData variable => NFData (TermLike variable) where
    rnf (Recursive.project -> annotation :< pat) =
        rnf annotation `seq` rnf pat `seq` ()

instance
    (SortedVariable variable, Unparse variable) =>
    Unparse (TermLike variable)
  where
    unparse (Recursive.project -> _ :< pat) = unparse pat
    unparse2 (Recursive.project -> _ :< pat) = unparse2 pat

type instance Base (TermLike variable) =
    CofreeF (TermLikeF variable) (Attribute.Pattern variable)

-- This instance implements all class functions for the TermLike newtype
-- because the their implementations for the inner type may be specialized.
instance Recursive (TermLike variable) where
    project = \(TermLike embedded) ->
        case Recursive.project embedded of
            Compose (Identity projected) -> TermLike <$> projected
    {-# INLINE project #-}

    -- This specialization is particularly important: The default implementation
    -- of 'cata' in terms of 'project' would involve an extra call to 'fmap' at
    -- every level of the tree due to the implementation of 'project' above.
    cata alg = \(TermLike fixed) ->
        Recursive.cata
            (\(Compose (Identity base)) -> alg base)
            fixed
    {-# INLINE cata #-}

    para alg = \(TermLike fixed) ->
        Recursive.para
            (\(Compose (Identity base)) ->
                 alg (Bifunctor.first TermLike <$> base)
            )
            fixed
    {-# INLINE para #-}

    gpara dist alg = \(TermLike fixed) ->
        Recursive.gpara
            (\(Compose (Identity base)) -> Compose . Identity <$> dist base)
            (\(Compose (Identity base)) -> alg (Env.local TermLike <$> base))
            fixed
    {-# INLINE gpara #-}

    prepro pre alg = \(TermLike fixed) ->
        Recursive.prepro
            (\(Compose (Identity base)) -> (Compose . Identity) (pre base))
            (\(Compose (Identity base)) -> alg base)
            fixed
    {-# INLINE prepro #-}

    gprepro dist pre alg = \(TermLike fixed) ->
        Recursive.gprepro
            (\(Compose (Identity base)) -> Compose . Identity <$> dist base)
            (\(Compose (Identity base)) -> (Compose . Identity) (pre base))
            (\(Compose (Identity base)) -> alg base)
            fixed
    {-# INLINE gprepro #-}

-- This instance implements all class functions for the TermLike newtype
-- because the their implementations for the inner type may be specialized.
instance Corecursive (TermLike variable) where
    embed = \projected ->
        (TermLike . Recursive.embed . Compose . Identity)
            (getTermLike <$> projected)
    {-# INLINE embed #-}

    ana coalg = TermLike . ana0
      where
        ana0 =
            Recursive.ana (Compose . Identity . coalg)
    {-# INLINE ana #-}

    apo coalg = TermLike . apo0
      where
        apo0 =
            Recursive.apo
                (\a ->
                     (Compose . Identity)
                        (Bifunctor.first getTermLike <$> coalg a)
                )
    {-# INLINE apo #-}

    postpro post coalg = TermLike . postpro0
      where
        postpro0 =
            Recursive.postpro
                (\(Compose (Identity base)) -> (Compose . Identity) (post base))
                (Compose . Identity . coalg)
    {-# INLINE postpro #-}

    gpostpro dist post coalg = TermLike . gpostpro0
      where
        gpostpro0 =
            Recursive.gpostpro
                (Compose . Identity . dist . (<$>) (runIdentity . getCompose))
                (\(Compose (Identity base)) -> (Compose . Identity) (post base))
                (Compose . Identity . coalg)
    {-# INLINE gpostpro #-}

instance TopBottom (TermLike variable) where
    isTop (Recursive.project -> _ :< TopF Top {}) = True
    isTop _ = False
    isBottom (Recursive.project -> _ :< BottomF Bottom {}) = True
    isBottom _ = False

extractAttributes :: TermLike variable -> Attribute.Pattern variable
extractAttributes = extract . getTermLike

instance Ord variable => Binding (TermLike variable) where
    type VariableType (TermLike variable) = variable

    traverseVariable match termLike =
        case termLikeHead of
            VariableF variable ->
                matched <$> match variable
              where
                matched variable' =
                    Recursive.embed (attrs' :< VariableF variable')
                  where
                    attrs' =
                        attrs
                            { Attribute.freeVariables =
                                FreeVariables.singleton variable'
                            }
            _ -> pure termLike
      where
        attrs :< termLikeHead = Recursive.project termLike

    traverseBinder match termLike@(Recursive.project -> attrs :< termLikeHead) =
        case termLikeHead of
            ExistsF exists -> matched <$> existsBinder match exists
              where
                matched exists' = Recursive.embed (attrs' :< ExistsF exists')
                  where
                    Exists { existsChild } = exists'
                    Exists { existsVariable } = exists'
                    attrs' =
                        attrs
                            { Attribute.freeVariables =
                                FreeVariables.delete existsVariable
                                $ freeVariables existsChild
                            }

            ForallF forall -> matched <$> forallBinder match forall
              where
                matched forall' = Recursive.embed (attrs' :< ForallF forall')
                  where
                    Forall { forallChild } = forall'
                    Forall { forallVariable } = forall'
                    attrs' =
                        attrs
                            { Attribute.freeVariables =
                                FreeVariables.delete forallVariable
                                $ freeVariables forallChild
                            }

            _ -> pure termLike

freeVariables :: TermLike variable -> FreeVariables variable
freeVariables = Attribute.freeVariables . extractAttributes

hasFreeVariable
    :: Ord variable
    => variable
    -> TermLike variable
    -> Bool
hasFreeVariable variable = FreeVariables.member variable . freeVariables

{- | Throw an error if the variable occurs free in the pattern.

Otherwise, the argument is returned.

 -}
withoutFreeVariable
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => variable  -- ^ variable
    -> TermLike variable
    -> a  -- ^ result, if the variable does not occur free in the pattern
    -> a
withoutFreeVariable variable termLike result
  | hasFreeVariable variable termLike =
    (error . show . Pretty.vsep)
        [ Pretty.hsep
            [ "Unexpected free variable"
            , unparse variable
            , "in pattern:"
            ]
        , Pretty.indent 4 (unparse termLike)
        ]
  | otherwise = result

{- | Use the provided mapping to replace all variables in a 'StepPattern'.

@mapVariables@ is lazy: it descends into its argument only as the result is
demanded. Intermediate allocation from composing multiple transformations with
@mapVariables@ is amortized; the intermediate trees are never fully resident.

__Warning__: @mapVariables@ will capture variables if the provided mapping is
not injective!

See also: 'traverseVariables'

 -}
mapVariables
    :: Ord variable2
    => (variable1 -> variable2)
    -> TermLike variable1
    -> TermLike variable2
mapVariables mapping =
    Recursive.unfold (mapVariablesWorker . Recursive.project)
  where
    mapVariablesWorker (attrs :< pat) =
        Attribute.mapVariables mapping attrs :< mapVariablesF mapping pat

{- | Use the provided traversal to replace all variables in a 'TermLike'.

@traverseVariables@ is strict, i.e. its argument is fully evaluated before it
returns. When composing multiple transformations with @traverseVariables@, the
intermediate trees will be fully allocated; @mapVariables@ is more composable in
this respect.

__Warning__: @traverseVariables@ will capture variables if the provided
traversal is not injective!

See also: 'mapVariables'

 -}
traverseVariables
    ::  forall m variable1 variable2.
        (Monad m, Ord variable2)
    => (variable1 -> m variable2)
    -> TermLike variable1
    -> m (TermLike variable2)
traverseVariables traversing =
    Recursive.fold traverseVariablesWorker
  where
    traverseVariablesWorker (attrs :< pat) =
        Recursive.embed <$> projected
      where
        projected =
            (:<)
                <$> Attribute.traverseVariables traversing attrs
                <*> (traverseVariablesF traversing =<< sequence pat)

{- | Construct a @'TermLike' 'Concrete'@ from any 'TermLike'.

A concrete pattern contains no variables, so @asConcreteStepPattern@ is
fully polymorphic on the variable type in the pure pattern. If the argument
contains any variables, the result is @Nothing@.

@asConcrete@ is strict, i.e. it traverses its argument entirely,
because the entire tree must be traversed to inspect for variables before
deciding if the result is @Nothing@ or @Just _@.

 -}
asConcrete
    :: TermLike variable
    -> Maybe (TermLike Concrete)
asConcrete = traverseVariables (\case { _ -> Nothing })

isConcrete :: TermLike variable -> Bool
isConcrete = isJust . asConcrete

{- | Construct any 'TermLike' from a @'TermLike' 'Concrete'@.

The concrete pattern contains no variables, so the result is fully
polymorphic in the variable type.

@fromConcrete@ unfolds the resulting syntax tree lazily, so it
composes with other tree transformations without allocating intermediates.

 -}
fromConcrete
    :: Ord variable
    => TermLike Concrete
    -> TermLike variable
fromConcrete = mapVariables (\case {})

{- | Traverse the pattern from the top down and apply substitutions.

The 'freeVariables' annotation is used to avoid traversing subterms that
contain none of the targeted variables.

The substitution must be normalized, i.e. no target (left-hand side) variable
may appear in the right-hand side of any substitution, but this is not checked.

 -}
substitute
    ::  ( FreshVariable variable
        , Ord variable
        , SortedVariable variable
        )
    =>  Map variable (TermLike variable)
    ->  TermLike variable
    ->  TermLike variable
substitute = Substitute.substitute lensFreeVariables

lensFreeVariables :: Lens.Lens' (TermLike variable) (FreeVariables variable)
lensFreeVariables mapping (Recursive.project -> attrs :< termLikeHead) =
    embed <$> Attribute.lensFreeVariables mapping attrs
  where
    embed = Recursive.embed . (:< termLikeHead)

{- | Reset the 'variableCounter' of all 'Variables'.

@externalizeFreshVariables@ resets the 'variableCounter' of all variables, while
ensuring that no 'Variable' in the result is accidentally captured.

 -}
externalizeFreshVariables :: TermLike Variable -> TermLike Variable
externalizeFreshVariables termLike =
    Reader.runReader
        (Recursive.fold externalizeFreshVariablesWorker termLike)
        renamedFreeVariables
  where
    -- | 'originalFreeVariables' are present in the original pattern; they do
    -- not have a generated counter. 'generatedFreeVariables' have a generated
    -- counter, usually because they were introduced by applying some axiom.
    (originalFreeVariables, generatedFreeVariables) =
        Set.partition Variable.isOriginalVariable
        $ FreeVariables.getFreeVariables $ freeVariables termLike

    -- | The map of generated free variables, renamed to be unique from the
    -- original free variables.
    (renamedFreeVariables, _) =
        Foldable.foldl' rename initial generatedFreeVariables
      where
        initial = (Map.empty, FreeVariables.FreeVariables originalFreeVariables)
        rename (renaming, avoiding) variable =
            let
                variable' = safeVariable avoiding variable
                renaming' = Map.insert variable variable' renaming
                avoiding' = FreeVariables.insert variable' avoiding
            in
                (renaming', avoiding')

    {- | Look up a variable renaming.

    The original (not generated) variables of the pattern are never renamed, so
    these variables are not present in the Map of renamed variables.

     -}
    lookupVariable variable =
        Reader.asks (Map.lookup variable) >>= \case
            Nothing -> return variable
            Just variable' -> return variable'

    {- | Externalize a variable safely.

    The variable's counter is incremented until its externalized form is unique
    among the set of avoided variables. The externalized form is returned.

     -}
    safeVariable avoiding variable =
        head  -- 'head' is safe because 'iterate' creates an infinite list
        $ dropWhile wouldCapture
        $ Variable.externalizeFreshVariable
        <$> iterate nextVariable variable
      where
        wouldCapture var = FreeVariables.member var avoiding

    underBinder freeVariables' variable child = do
        let variable' = safeVariable freeVariables' variable
        child' <- Reader.local (Map.insert variable variable') child
        return (variable', child')

    externalizeFreshVariablesWorker
        ::  Base
                (TermLike Variable)
                (Reader
                    (Map Variable Variable)
                    (TermLike Variable)
                )
        ->  Reader
                (Map Variable Variable)
                (TermLike Variable)
    externalizeFreshVariablesWorker (attrs :< patt) = do
        attrs' <- Attribute.traverseVariables lookupVariable attrs
        let freeVariables' = Attribute.freeVariables attrs'
        patt' <-
            case patt of
                ExistsF exists -> do
                    let Exists { existsVariable, existsChild } = exists
                    (existsVariable', existsChild') <-
                        underBinder
                            freeVariables'
                            existsVariable
                            existsChild
                    let exists' =
                            exists
                                { existsVariable = existsVariable'
                                , existsChild = existsChild'
                                }
                    return (ExistsF exists')
                ForallF forall -> do
                    let Forall { forallVariable, forallChild } = forall
                    (forallVariable', forallChild') <-
                        underBinder
                            freeVariables'
                            forallVariable
                            forallChild
                    let forall' =
                            forall
                                { forallVariable = forallVariable'
                                , forallChild = forallChild'
                                }
                    return (ForallF forall')
                _ ->
                    traverseVariablesF lookupVariable patt >>= sequence
        (return . Recursive.embed) (attrs' :< patt')

-- | Get the 'Sort' of a 'TermLike' from the 'Attribute.Pattern' annotation.
termLikeSort :: TermLike variable -> Sort
termLikeSort = Attribute.patternSort . extractAttributes

-- | Attempts to modify p to have sort s.
forceSort
    :: (SortedVariable variable, Unparse variable, GHC.HasCallStack)
    => Sort
    -> TermLike variable
    -> TermLike variable
forceSort forcedSort = Recursive.apo forceSortWorker
  where
    forceSortWorker original@(Recursive.project -> attrs :< pattern') =
        (:<)
            (attrs { Attribute.patternSort = forcedSort })
            (case attrs of
                Attribute.Pattern { patternSort = sort }
                  | sort == forcedSort    -> Left <$> pattern'
                  | sort == predicateSort -> forceSortWorkerPredicate
                  | otherwise             -> illSorted
            )
      where
        illSorted =
            (error . show . Pretty.vsep)
            [ Pretty.cat
                [ "Could not force pattern to sort "
                , Pretty.squotes (unparse forcedSort)
                , ":"
                ]
            , Pretty.indent 4 (unparse original)
            ]
        forceSortWorkerPredicate =
            case pattern' of
                -- Recurse
                EvaluatedF evaluated -> EvaluatedF (Right <$> evaluated)
                -- Predicates: Force sort and stop.
                BottomF bottom' -> BottomF bottom' { bottomSort = forcedSort }
                TopF top' -> TopF top' { topSort = forcedSort }
                CeilF ceil' -> CeilF (Left <$> ceil'')
                  where
                    ceil'' = ceil' { ceilResultSort = forcedSort }
                FloorF floor' -> FloorF (Left <$> floor'')
                  where
                    floor'' = floor' { floorResultSort = forcedSort }
                EqualsF equals' -> EqualsF (Left <$> equals'')
                  where
                    equals'' = equals' { equalsResultSort = forcedSort }
                InF in' -> InF (Left <$> in'')
                  where
                    in'' = in' { inResultSort = forcedSort }
                -- Connectives: Force sort and recurse.
                AndF and' -> AndF (Right <$> and'')
                  where
                    and'' = and' { andSort = forcedSort }
                OrF or' -> OrF (Right <$> or'')
                  where
                    or'' = or' { orSort = forcedSort }
                IffF iff' -> IffF (Right <$> iff'')
                  where
                    iff'' = iff' { iffSort = forcedSort }
                ImpliesF implies' -> ImpliesF (Right <$> implies'')
                  where
                    implies'' = implies' { impliesSort = forcedSort }
                NotF not' -> NotF (Right <$> not'')
                  where
                    not'' = not' { notSort = forcedSort }
                NextF next' -> NextF (Right <$> next'')
                  where
                    next'' = next' { nextSort = forcedSort }
                RewritesF rewrites' -> RewritesF (Right <$> rewrites'')
                  where
                    rewrites'' = rewrites' { rewritesSort = forcedSort }
                ExistsF exists' -> ExistsF (Right <$> exists'')
                  where
                    exists'' = exists' { existsSort = forcedSort }
                ForallF forall' -> ForallF (Right <$> forall'')
                  where
                    forall'' = forall' { forallSort = forcedSort }
                -- Rigid: These patterns should never have sort _PREDICATE{}.
                MuF _ -> illSorted
                NuF _ -> illSorted
                ApplySymbolF _ -> illSorted
                ApplyAliasF _ -> illSorted
                BuiltinF _ -> illSorted
                DomainValueF _ -> illSorted
                CharLiteralF _ -> illSorted
                StringLiteralF _ -> illSorted
                VariableF _ -> illSorted
                InhabitantF _ -> illSorted
                SetVariableF _ -> illSorted

{- | Call the argument function with two patterns whose sorts agree.

If one pattern is flexibly sorted, the result is the rigid sort of the other
pattern. If both patterns are flexibly sorted, then the result is
'predicateSort'. If both patterns have the same rigid sort, that is the
result. It is an error if the patterns are rigidly sorted but do not have the
same sort.

 -}
makeSortsAgree
    :: (SortedVariable variable, Unparse variable, GHC.HasCallStack)
    => (TermLike variable -> TermLike variable -> Sort -> a)
    -> TermLike variable
    -> TermLike variable
    -> a
makeSortsAgree withPatterns = \pattern1 pattern2 ->
    let
        sort1 = getRigidSort pattern1
        sort2 = getRigidSort pattern2
        sort = fromMaybe predicateSort (sort1 <|> sort2)
        !pattern1' = forceSort sort pattern1
        !pattern2' = forceSort sort pattern2
    in
        withPatterns pattern1' pattern2' sort
{-# INLINE makeSortsAgree #-}

getRigidSort :: TermLike variable -> Maybe Sort
getRigidSort pattern' =
    case termLikeSort pattern' of
        sort
          | sort == predicateSort -> Nothing
          | otherwise -> Just sort

{- | Construct an 'And' pattern.
 -}
mkAnd
    ::  ( Ord variable
        , SortedVariable variable
        , Unparse variable
        , GHC.HasCallStack
        )
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
mkAnd = makeSortsAgree mkAndWorker
  where
    mkAndWorker andFirst andSecond andSort =
        Recursive.embed (attrs :< AndF and')
      where
        attrs =
            Attribute.Pattern
                { patternSort = andSort
                , freeVariables = freeVariables1 <> freeVariables2
                }
        and' = And { andSort, andFirst, andSecond }
        freeVariables1 = freeVariables andFirst
        freeVariables2 = freeVariables andSecond

{- | Force the 'TermLike's to conform to their 'Sort's.

It is an error if the lists are not the same length, or if any 'TermLike' cannot
be coerced to its corresponding 'Sort'.

See also: 'forceSort'

 -}
forceSorts
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => [Sort]
    -> [TermLike variable]
    -> [TermLike variable]
forceSorts operandSorts children =
    alignWith forceTheseSorts operandSorts children
  where
    forceTheseSorts (This _) =
        (error . show . Pretty.vsep) ("Too few arguments:" : expected)
    forceTheseSorts (That _) =
        (error . show . Pretty.vsep) ("Too many arguments:" : expected)
    forceTheseSorts (These sort termLike) = forceSort sort termLike
    expected =
        [ "Expected:"
        , Pretty.indent 4 (Unparser.arguments operandSorts)
        , "but found:"
        , Pretty.indent 4 (Unparser.arguments children)
        ]

{- | Construct an 'Application' pattern.

The result sort of the 'Alias' must be provided. The sorts of arguments
are not checked. Use 'applySymbol' or 'applyAlias' whenever possible to avoid
these shortcomings.

See also: 'applyAlias', 'applySymbol'

 -}
mkApplyAlias
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => Alias
    -- ^ Application symbol or alias
    -> [TermLike variable]
    -- ^ Application arguments
    -> TermLike variable
mkApplyAlias alias children =
    Recursive.embed (attrs :< ApplyAliasF application)
  where
    attrs =
        Attribute.Pattern
            { patternSort = resultSort
            , freeVariables = mconcat (freeVariables <$> children)
            }
    application =
        Application
            { applicationSymbolOrAlias = alias
            , applicationChildren = forceSorts operandSorts children
            }
    Alias { aliasSorts } = alias
    operandSorts = applicationSortsOperands aliasSorts
    resultSort = applicationSortsResult aliasSorts

{- | Construct an 'Application' pattern.

The result sort of the 'SymbolOrAlias' must be provided. The sorts of arguments
are not checked. Use 'applySymbol' or 'applyAlias' whenever possible to avoid
these shortcomings.

See also: 'applyAlias', 'applySymbol'

 -}
mkApplySymbol
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => Symbol
    -- ^ Application symbol or alias
    -> [TermLike variable]
    -- ^ Application arguments
    -> TermLike variable
mkApplySymbol symbol children =
    Recursive.embed (attrs :< ApplySymbolF application)
  where
    attrs =
        Attribute.Pattern
            { patternSort = resultSort
            , freeVariables = mconcat (freeVariables <$> children)
            }
    application =
        Application
            { applicationSymbolOrAlias = symbol
            , applicationChildren = forceSorts operandSorts children
            }
    Symbol { symbolSorts } = symbol
    operandSorts = applicationSortsOperands symbolSorts
    resultSort = applicationSortsResult symbolSorts

{- | Construct an 'Application' pattern from a 'Alias' declaration.

The provided sort parameters must match the declaration.

See also: 'mkApplyAlias', 'applyAlias_', 'applySymbol', 'mkAlias'

 -}
applyAlias
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => SentenceAlias (TermLike variable)
    -- ^ 'Alias' declaration
    -> [Sort]
    -- ^ 'Alias' sort parameters
    -> [TermLike variable]
    -- ^ 'Application' arguments
    -> TermLike variable
applyAlias sentence params children =
    mkApplyAlias internal children'
  where
    SentenceAlias { sentenceAliasAlias = external } = sentence
    Syntax.Alias { aliasConstructor } = external
    Syntax.Alias { aliasParams } = external
    internal =
        Alias
            { aliasConstructor
            , aliasParams = params
            , aliasSorts =
                symbolOrAliasSorts params sentence
                & assertRight
            }
    substitution = sortSubstitution aliasParams params
    childSorts = substituteSortVariables substitution <$> sentenceAliasSorts
      where
        SentenceAlias { sentenceAliasSorts } = sentence
    children' = alignWith forceChildSort childSorts children
      where
        forceChildSort =
            \case
                These sort pattern' -> forceSort sort pattern'
                This _ ->
                    (error . show . Pretty.vsep)
                        ("Too few parameters:" : expected)
                That _ ->
                    (error . show . Pretty.vsep)
                        ("Too many parameters:" : expected)
        expected =
            [ "Expected:"
            , Pretty.indent 4 (Unparser.arguments childSorts)
            , "but found:"
            , Pretty.indent 4 (Unparser.arguments children)
            ]

{- | Construct an 'Application' pattern from a 'Alias' declaration.

The 'Alias' must not be declared with sort parameters.

See also: 'mkApp', 'applyAlias'

 -}
applyAlias_
    ::  ( Ord variable
        , SortedVariable variable
        , Unparse variable
        , GHC.HasCallStack
        )
    => SentenceAlias (TermLike variable)
    -> [TermLike variable]
    -> TermLike variable
applyAlias_ sentence = applyAlias sentence []

{- | Construct an 'Application' pattern from a 'Symbol' declaration.

The provided sort parameters must match the declaration.

See also: 'mkApp', 'applySymbol_', 'mkSymbol'

 -}
applySymbol
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => SentenceSymbol pattern''
    -- ^ 'Symbol' declaration
    -> [Sort]
    -- ^ 'Symbol' sort parameters
    -> [TermLike variable]
    -- ^ 'Application' arguments
    -> TermLike variable
applySymbol sentence params children =
    mkApplySymbol internal children
  where
    SentenceSymbol { sentenceSymbolSymbol = external } = sentence
    Syntax.Symbol { symbolConstructor } = external
    internal =
        Symbol
            { symbolConstructor
            , symbolParams = params
            , symbolAttributes = Default.def
            , symbolSorts =
                symbolOrAliasSorts params sentence
                & assertRight
            }

{- | Construct an 'Application' pattern from a 'Symbol' declaration.

The 'Symbol' must not be declared with sort parameters.

See also: 'mkApplySymbol', 'applySymbol'

 -}
applySymbol_
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => SentenceSymbol pattern''
    -> [TermLike variable]
    -> TermLike variable
applySymbol_ sentence = applySymbol sentence []

{- | Construct a 'Bottom' pattern in the given sort.

See also: 'mkBottom_'

 -}
mkBottom :: Ord variable => Sort -> TermLike variable
mkBottom bottomSort =
    Recursive.embed (attrs :< BottomF bottom)
  where
    attrs =
        Attribute.Pattern
            { patternSort = bottomSort
            , freeVariables = mempty
            }
    bottom = Bottom { bottomSort }

{- | Construct a 'Bottom' pattern in 'predicateSort'.

This should not be used outside "Kore.Predicate.Predicate"; please use
'mkBottom' instead.

See also: 'mkBottom'

 -}
mkBottom_ :: Ord variable => TermLike variable
mkBottom_ = mkBottom predicateSort

{- | Construct a 'Ceil' pattern in the given sort.

See also: 'mkCeil_'

 -}
mkCeil :: Sort -> TermLike variable -> TermLike variable
mkCeil ceilResultSort ceilChild =
    Recursive.embed (attrs :< CeilF ceil)
  where
    ceilOperandSort = termLikeSort ceilChild
    attrs =
        Attribute.Pattern
            { patternSort = ceilResultSort
            , freeVariables = freeVariables ceilChild
            }
    ceil = Ceil { ceilOperandSort, ceilResultSort, ceilChild }

{- | Construct a 'Ceil' pattern in 'predicateSort'.

This should not be used outside "Kore.Predicate.Predicate"; please use 'mkCeil'
instead.

See also: 'mkCeil'

 -}
mkCeil_ :: TermLike variable -> TermLike variable
mkCeil_ = mkCeil predicateSort

{- | Construct a builtin pattern.
 -}
mkBuiltin
    :: Ord variable
    => Domain.Builtin (TermLike Concrete) (TermLike variable)
    -> TermLike variable
mkBuiltin domain =
    Recursive.embed (attrs :< BuiltinF domain)
  where
    attrs =
        Attribute.Pattern
            { patternSort = domainValueSort
            , freeVariables =
                (mconcat . Foldable.toList) (freeVariables <$> domain)
            }
    DomainValue { domainValueSort } = Lens.view lensDomainValue domain

{- | Construct a 'DomainValue' pattern.
 -}
mkDomainValue
    :: Ord variable
    => DomainValue Sort (TermLike variable)
    -> TermLike variable
mkDomainValue domain =
    Recursive.embed (attrs :< DomainValueF domain)
  where
    attrs =
        Attribute.Pattern
            { patternSort = domainValueSort domain
            , freeVariables =
                (mconcat . Foldable.toList) (freeVariables <$> domain)
            }

{- | Construct an 'Equals' pattern in the given sort.

See also: 'mkEquals_'

 -}
mkEquals
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => Sort
    -> TermLike variable
    -> TermLike variable
    -> TermLike variable
mkEquals equalsResultSort =
    makeSortsAgree mkEquals'Worker
  where
    mkEquals'Worker equalsFirst equalsSecond equalsOperandSort =
        Recursive.embed (attrs :< EqualsF equals)
      where
        attrs =
            Attribute.Pattern
                { patternSort = equalsResultSort
                , freeVariables = freeVariables1 <> freeVariables2
                }
        freeVariables1 = freeVariables equalsFirst
        freeVariables2 = freeVariables equalsSecond
        equals =
            Equals
                { equalsOperandSort
                , equalsResultSort
                , equalsFirst
                , equalsSecond
                }

{- | Construct a 'Equals' pattern in 'predicateSort'.

This should not be used outside "Kore.Predicate.Predicate"; please use
'mkEquals' instead.

See also: 'mkEquals'

 -}
mkEquals_
    ::  ( Ord variable
        , SortedVariable variable
        , Unparse variable
        , GHC.HasCallStack
        )
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
mkEquals_ = mkEquals predicateSort

{- | Construct an 'Exists' pattern.
 -}
mkExists
    :: Ord variable
    => variable
    -> TermLike variable
    -> TermLike variable
mkExists existsVariable existsChild =
    Recursive.embed (attrs :< ExistsF exists)
  where
    attrs =
        Attribute.Pattern
            { patternSort = existsSort
            , freeVariables =
                FreeVariables.delete existsVariable freeVariablesChild
            }
    existsSort = termLikeSort existsChild
    freeVariablesChild = freeVariables existsChild
    exists = Exists { existsSort, existsVariable, existsChild }

{- | Construct a 'Floor' pattern in the given sort.

See also: 'mkFloor_'

 -}
mkFloor
    :: Sort
    -> TermLike variable
    -> TermLike variable
mkFloor floorResultSort floorChild =
    Recursive.embed (attrs :< FloorF floor')
  where
    attrs =
        Attribute.Pattern
            { patternSort = floorResultSort
            , freeVariables = freeVariables floorChild
            }
    floorOperandSort = termLikeSort floorChild
    floor' = Floor { floorOperandSort, floorResultSort, floorChild }

{- | Construct a 'Floor' pattern in 'predicateSort'.

This should not be used outside "Kore.Predicate.Predicate"; please use 'mkFloor'
instead.

See also: 'mkFloor'

 -}
mkFloor_ :: TermLike variable -> TermLike variable
mkFloor_ = mkFloor predicateSort

{- | Construct a 'Forall' pattern.
 -}
mkForall
    :: Ord variable
    => variable
    -> TermLike variable
    -> TermLike variable
mkForall forallVariable forallChild =
    Recursive.embed (attrs :< ForallF forall)
  where
    attrs =
        Attribute.Pattern
            { patternSort = forallSort
            , freeVariables =
                FreeVariables.delete forallVariable freeVariablesChild
            }
    forallSort = termLikeSort forallChild
    freeVariablesChild = freeVariables forallChild
    forall = Forall { forallSort, forallVariable, forallChild }

{- | Construct an 'Iff' pattern.
 -}
mkIff
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
mkIff = makeSortsAgree mkIffWorker
  where
    mkIffWorker iffFirst iffSecond iffSort =
        Recursive.embed (attrs :< IffF iff')
      where
        attrs =
            Attribute.Pattern
                { patternSort = iffSort
                , freeVariables = freeVariables1 <> freeVariables2
                }
        freeVariables1 = freeVariables iffFirst
        freeVariables2 = freeVariables iffSecond
        iff' = Iff { iffSort, iffFirst, iffSecond }

{- | Construct an 'Implies' pattern.
 -}
mkImplies
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
mkImplies = makeSortsAgree mkImpliesWorker
  where
    mkImpliesWorker impliesFirst impliesSecond impliesSort =
        Recursive.embed (attrs :< ImpliesF implies')
      where
        attrs =
            Attribute.Pattern
                { patternSort = impliesSort
                , freeVariables = freeVariables1 <> freeVariables2
                }
        freeVariables1 = freeVariables impliesFirst
        freeVariables2 = freeVariables impliesSecond
        implies' = Implies { impliesSort, impliesFirst, impliesSecond }

{- | Construct a 'In' pattern in the given sort.

See also: 'mkIn_'

 -}
mkIn
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => Sort
    -> TermLike variable
    -> TermLike variable
    -> TermLike variable
mkIn inResultSort = makeSortsAgree mkInWorker
  where
    mkInWorker inContainedChild inContainingChild inOperandSort =
        Recursive.embed (attrs :< InF in')
      where
        attrs =
            Attribute.Pattern
                { patternSort = inResultSort
                , freeVariables = freeVariables1 <> freeVariables2
                }
        freeVariables1 = freeVariables inContainedChild
        freeVariables2 = freeVariables inContainingChild
        in' =
            In
                { inOperandSort
                , inResultSort
                , inContainedChild
                , inContainingChild
                }

{- | Construct a 'In' pattern in 'predicateSort'.

This should not be used outside "Kore.Predicate.Predicate"; please use 'mkIn'
instead.

See also: 'mkIn'

 -}
mkIn_
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
mkIn_ = mkIn predicateSort

{- | Construct a 'Mu' pattern.
 -}
mkMu
    :: Ord variable
    => SortedVariable variable
    => Unparse variable
    => SetVariable variable
    -> TermLike variable
    -> TermLike variable
mkMu muVar = makeSortsAgree mkMuWorker (mkSetVar muVar)
  where
    mkMuWorker (SetVar_ muVariable) muChild _ =
           Recursive.embed (attrs :< MuF mu)
      where
        attrs =
            Attribute.Pattern
                { patternSort = sortedVariableSort v
                , freeVariables = FreeVariables.delete v freeVariablesChild
                }
        v = getVariable muVariable
        freeVariablesChild = freeVariables muChild
        mu = Mu { muVariable, muChild }
    mkMuWorker _ _ _ = error "Unreachable code"

{- | Construct a 'Next' pattern.
 -}
mkNext :: TermLike variable -> TermLike variable
mkNext nextChild =
    Recursive.embed (attrs :< NextF next)
  where
    attrs =
        Attribute.Pattern
            { patternSort = nextSort
            , freeVariables = freeVariables nextChild
            }
    nextSort = termLikeSort nextChild
    next = Next { nextSort, nextChild }

{- | Construct a 'Not' pattern.
 -}
mkNot :: TermLike variable -> TermLike variable
mkNot notChild =
    Recursive.embed (attrs :< NotF not')
  where
    attrs =
        Attribute.Pattern
            { patternSort = notSort
            , freeVariables = freeVariables notChild
            }
    notSort = termLikeSort notChild
    not' = Not { notSort, notChild }

{- | Construct a 'Nu' pattern.
 -}
mkNu
    :: Ord variable
    => SortedVariable variable
    => Unparse variable
    => SetVariable variable
    -> TermLike variable
    -> TermLike variable
mkNu nuVar = makeSortsAgree mkNuWorker (mkSetVar nuVar)
  where
    mkNuWorker (SetVar_ nuVariable) nuChild _ =
           Recursive.embed (attrs :< NuF nu)
      where
        attrs =
            Attribute.Pattern
                { patternSort = sortedVariableSort v
                , freeVariables = FreeVariables.delete v freeVariablesChild
                }
        v = getVariable nuVariable
        freeVariablesChild = freeVariables nuChild
        nu = Nu { nuVariable, nuChild }
    mkNuWorker _ _ _ = error "Unreachable code"

{- | Construct an 'Or' pattern.
 -}
mkOr
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
mkOr = makeSortsAgree mkOrWorker
  where
    mkOrWorker orFirst orSecond orSort =
        Recursive.embed (attrs :< OrF or')
      where
        attrs =
            Attribute.Pattern
                { patternSort = orSort
                , freeVariables = freeVariables1 <> freeVariables2
                }
        freeVariables1 = freeVariables orFirst
        freeVariables2 = freeVariables orSecond
        or' = Or { orSort, orFirst, orSecond }

{- | Construct a 'Rewrites' pattern.
 -}
mkRewrites
    :: (Ord variable, SortedVariable variable, Unparse variable)
    => GHC.HasCallStack
    => TermLike variable
    -> TermLike variable
    -> TermLike variable
mkRewrites = makeSortsAgree mkRewritesWorker
  where
    mkRewritesWorker rewritesFirst rewritesSecond rewritesSort =
        Recursive.embed (attrs :< RewritesF rewrites')
      where
        attrs =
            Attribute.Pattern
                { patternSort = rewritesSort
                , freeVariables = freeVariables1 <> freeVariables2
                }
        freeVariables1 = freeVariables rewritesFirst
        freeVariables2 = freeVariables rewritesSecond
        rewrites' = Rewrites { rewritesSort, rewritesFirst, rewritesSecond }

{- | Construct a 'Top' pattern in the given sort.

See also: 'mkTop_'

 -}
mkTop :: Ord variable => Sort -> TermLike variable
mkTop topSort =
    Recursive.embed (attrs :< TopF top)
  where
    attrs =
        Attribute.Pattern
            { patternSort = topSort
            , freeVariables = mempty
            }
    top = Top { topSort }

{- | Construct a 'Top' pattern in 'predicateSort'.

This should not be used outside "Kore.Predicate.Predicate"; please use
'mkTop' instead.

See also: 'mkTop'

 -}
mkTop_ :: Ord variable => TermLike variable
mkTop_ = mkTop predicateSort

{- | Construct a variable pattern.
 -}
mkVar
    :: (Ord variable, SortedVariable variable)
    => variable
    -> TermLike variable
mkVar var = Recursive.embed (validVar var :< VariableF var)

validVar
    :: (Ord variable, SortedVariable variable)
    => variable
    -> Attribute.Pattern variable
validVar var =
    Attribute.Pattern
        { patternSort = sortedVariableSort var
        , freeVariables = FreeVariables.singleton var
        }

{- | Construct a set variable pattern.
 -}
mkSetVar
    :: (Ord variable, SortedVariable variable)
    => SetVariable variable
    -> TermLike variable
mkSetVar setVar@(SetVariable var) =
    Recursive.embed (validVar var :< SetVariableF setVar)

{- | Construct a 'StringLiteral' pattern.
 -}
mkStringLiteral :: Ord variable => Text -> TermLike variable
mkStringLiteral string =
    Recursive.embed (attrs :< StringLiteralF stringLiteral)
  where
    attrs =
        Attribute.Pattern
            { patternSort = stringMetaSort
            , freeVariables = mempty
            }
    stringLiteral = StringLiteral string

{- | Construct a 'CharLiteral' pattern.
 -}
mkCharLiteral :: Ord variable => Char -> TermLike variable
mkCharLiteral char =
    Recursive.embed (attrs :< CharLiteralF charLiteral)
  where
    attrs = Attribute.Pattern
        { patternSort = charMetaSort
        , freeVariables = mempty
        }
    charLiteral = CharLiteral char

mkInhabitant :: Ord variable => Sort -> TermLike variable
mkInhabitant sort =
    Recursive.embed (attrs :< InhabitantF sort)
  where
    attrs =
        Attribute.Pattern
            { patternSort = sort
            , freeVariables = mempty
            }

mkEvaluated :: TermLike variable -> TermLike variable
mkEvaluated termLike =
    Recursive.embed
        (extractAttributes termLike :< EvaluatedF (Evaluated termLike))

mkSort :: Id -> Sort
mkSort name = SortActualSort $ SortActual name []

mkSortVariable :: Id -> Sort
mkSortVariable name = SortVariableSort $ SortVariable name

-- | Construct a variable with a given name and sort
-- "x" `varS` s
varS :: Text -> Sort -> Variable
varS x variableSort =
    Variable
        { variableName = noLocationId x
        , variableSort
        , variableCounter = mempty
        }

{- | Construct an axiom declaration with the given parameters and pattern.
 -}
mkAxiom
    :: [SortVariable]
    -> TermLike variable
    -> SentenceAxiom (TermLike variable)
mkAxiom sentenceAxiomParameters sentenceAxiomPattern =
    SentenceAxiom
        { sentenceAxiomParameters
        , sentenceAxiomPattern
        , sentenceAxiomAttributes = Attributes []
        }

{- | Construct an axiom declaration with no parameters.

See also: 'mkAxiom'

 -}
mkAxiom_ :: TermLike variable -> SentenceAxiom (TermLike variable)
mkAxiom_ = mkAxiom []

{- | Construct a symbol declaration with the given parameters and sorts.
 -}
mkSymbol
    :: Id
    -> [SortVariable]
    -> [Sort]
    -> Sort
    -> SentenceSymbol (TermLike variable)
mkSymbol symbolConstructor symbolParams argumentSorts resultSort' =
    SentenceSymbol
        { sentenceSymbolSymbol =
            Syntax.Symbol
                { symbolConstructor
                , symbolParams
                }
        , sentenceSymbolSorts = argumentSorts
        , sentenceSymbolResultSort = resultSort'
        , sentenceSymbolAttributes = Attributes []
        }

{- | Construct a symbol declaration with no parameters.

See also: 'mkSymbol'

 -}
mkSymbol_
    :: Id
    -> [Sort]
    -> Sort
    -> SentenceSymbol (TermLike variable)
mkSymbol_ symbolConstructor = mkSymbol symbolConstructor []

{- | Construct an alias declaration with the given parameters and sorts.
 -}
mkAlias
    :: Id
    -> [SortVariable]
    -> Sort
    -> [Variable]
    -> TermLike Variable
    -> SentenceAlias (TermLike Variable)
mkAlias aliasConstructor aliasParams resultSort' arguments right =
    SentenceAlias
        { sentenceAliasAlias =
            Syntax.Alias
                { aliasConstructor
                , aliasParams
                }
        , sentenceAliasSorts = argumentSorts
        , sentenceAliasResultSort = resultSort'
        , sentenceAliasLeftPattern =
            Application
                { applicationSymbolOrAlias =
                    SymbolOrAlias
                        { symbolOrAliasConstructor = aliasConstructor
                        , symbolOrAliasParams =
                            SortVariableSort <$> aliasParams
                        }
                , applicationChildren = arguments
                }
        , sentenceAliasRightPattern = right
        , sentenceAliasAttributes = Attributes []
        }
  where
    argumentSorts = variableSort <$> arguments

{- | Construct an alias declaration with no parameters.

See also: 'mkAlias'

 -}
mkAlias_
    :: Id
    -> Sort
    -> [Variable]
    -> (TermLike Variable)
    -> SentenceAlias (TermLike Variable)
mkAlias_ aliasConstructor = mkAlias aliasConstructor []

pattern And_
    :: Sort
    -> TermLike variable
    -> TermLike variable
    -> TermLike variable

pattern App_
    :: Symbol
    -> [TermLike variable]
    -> TermLike variable

pattern ApplyAlias_
    :: Alias
    -> [TermLike variable]
    -> TermLike variable

pattern Bottom_
    :: Sort
    -> TermLike variable

pattern Ceil_
    :: Sort
    -> Sort
    -> TermLike variable
    -> TermLike variable

pattern DV_
    :: Sort
    -> TermLike variable
    -> TermLike variable

pattern Builtin_
    :: Domain.Builtin (TermLike Concrete) (TermLike variable)
    -> TermLike variable

pattern Equals_
    :: Sort
    -> Sort
    -> TermLike variable
    -> TermLike variable
    -> TermLike variable

pattern Exists_
    :: Sort
    -> variable
    -> TermLike variable
    -> TermLike variable

pattern Floor_
    :: Sort
    -> Sort
    -> TermLike variable
    -> TermLike variable

pattern Forall_
    :: Sort
    -> variable
    -> TermLike variable
    -> TermLike variable

pattern Iff_
    :: Sort
    -> TermLike variable
    -> TermLike variable
    -> TermLike variable

pattern Implies_
    :: Sort
    -> TermLike variable
    -> TermLike variable
    -> TermLike variable

pattern In_
    :: Sort
    -> Sort
    -> TermLike variable
    -> TermLike variable
    -> TermLike variable

pattern Next_
    :: Sort
    -> TermLike variable
    -> TermLike variable

pattern Not_
    :: Sort
    -> TermLike variable
    -> TermLike variable

pattern Or_
    :: Sort
    -> TermLike variable
    -> TermLike variable
    -> TermLike variable

pattern Rewrites_
  :: Sort
  -> TermLike variable
  -> TermLike variable
  -> TermLike variable

pattern Top_ :: Sort -> TermLike variable

pattern Var_ :: variable -> TermLike variable

pattern SetVar_ :: SetVariable variable -> TermLike variable

pattern StringLiteral_ :: Text -> TermLike variable

pattern CharLiteral_ :: Char -> TermLike variable

pattern Evaluated_ :: TermLike variable -> TermLike variable

pattern And_ andSort andFirst andSecond <-
    (Recursive.project -> _ :< AndF And { andSort, andFirst, andSecond })

pattern ApplyAlias_ applicationSymbolOrAlias applicationChildren <-
    (Recursive.project ->
        _ :< ApplyAliasF Application
            { applicationSymbolOrAlias
            , applicationChildren
            }
    )

pattern App_ applicationSymbolOrAlias applicationChildren <-
    (Recursive.project ->
        _ :< ApplySymbolF Application
            { applicationSymbolOrAlias
            , applicationChildren
            }
    )

pattern Bottom_ bottomSort <-
    (Recursive.project -> _ :< BottomF Bottom { bottomSort })

pattern Ceil_ ceilOperandSort ceilResultSort ceilChild <-
    (Recursive.project ->
        _ :< CeilF Ceil { ceilOperandSort, ceilResultSort, ceilChild }
    )

pattern DV_ domainValueSort domainValueChild <-
    (Recursive.project ->
        _ :< DomainValueF DomainValue { domainValueSort, domainValueChild }
    )

pattern Builtin_ builtin <- (Recursive.project -> _ :< BuiltinF builtin)

pattern Equals_ equalsOperandSort equalsResultSort equalsFirst equalsSecond <-
    (Recursive.project ->
        _ :< EqualsF Equals
            { equalsOperandSort
            , equalsResultSort
            , equalsFirst
            , equalsSecond
            }
    )

pattern Exists_ existsSort existsVariable existsChild <-
    (Recursive.project ->
        _ :< ExistsF Exists { existsSort, existsVariable, existsChild }
    )

pattern Floor_ floorOperandSort floorResultSort floorChild <-
    (Recursive.project ->
        _ :< FloorF Floor
            { floorOperandSort
            , floorResultSort
            , floorChild
            }
    )

pattern Forall_ forallSort forallVariable forallChild <-
    (Recursive.project ->
        _ :< ForallF Forall { forallSort, forallVariable, forallChild }
    )

pattern Iff_ iffSort iffFirst iffSecond <-
    (Recursive.project ->
        _ :< IffF Iff { iffSort, iffFirst, iffSecond }
    )

pattern Implies_ impliesSort impliesFirst impliesSecond <-
    (Recursive.project ->
        _ :< ImpliesF Implies { impliesSort, impliesFirst, impliesSecond }
    )

pattern In_ inOperandSort inResultSort inFirst inSecond <-
    (Recursive.project ->
        _ :< InF In
            { inOperandSort
            , inResultSort
            , inContainedChild = inFirst
            , inContainingChild = inSecond
            }
    )

pattern Next_ nextSort nextChild <-
    (Recursive.project ->
        _ :< NextF Next { nextSort, nextChild })

pattern Not_ notSort notChild <-
    (Recursive.project ->
        _ :< NotF Not { notSort, notChild })

pattern Or_ orSort orFirst orSecond <-
    (Recursive.project -> _ :< OrF Or { orSort, orFirst, orSecond })

pattern Rewrites_ rewritesSort rewritesFirst rewritesSecond <-
    (Recursive.project ->
        _ :< RewritesF Rewrites
            { rewritesSort
            , rewritesFirst
            , rewritesSecond
            }
    )

pattern Top_ topSort <-
    (Recursive.project -> _ :< TopF Top { topSort })

pattern Var_ variable <-
    (Recursive.project -> _ :< VariableF variable)

pattern SetVar_ setVariable <-
    (Recursive.project -> _ :< SetVariableF setVariable)

pattern V :: variable -> TermLike variable
pattern V x <- Var_ x

pattern StringLiteral_ str <-
    (Recursive.project -> _ :< StringLiteralF (StringLiteral str))

pattern CharLiteral_ char <-
    (Recursive.project -> _ :< CharLiteralF (CharLiteral char))

pattern Evaluated_ child <-
    (Recursive.project -> _ :< EvaluatedF (Evaluated child))

{-|
Module      : Kore.AST.Pure
Description : Kore patterns specialized to a specific level
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : traian.serbanuta@runtimeverification.com

-}
module Kore.AST.Pure
    ( PurePattern (..)
    , CommonPurePattern
    , ConcretePurePattern
    , VerifiedPurePattern
    , asPurePattern
    , fromPurePattern
    , eraseAnnotations
    , traverseVariables
    , mapVariables
    , asConcretePurePattern
    , isConcrete
    , fromConcretePurePattern
    , castVoidDomainValues
    -- * Pure pattern heads
    , groundHead
    , constant
    -- * Re-exports
    , Base, CofreeF (..)
    , module Control.Comonad
    , module Kore.AST.Common
    , module Kore.Syntax
    ) where

import           Control.Comonad
import           Control.Comonad.Trans.Cofree
                 ( Cofree, CofreeF (..), ComonadCofree (..) )
import qualified Control.Comonad.Trans.Env as Env
import           Control.DeepSeq
                 ( NFData (..) )
import qualified Data.Bifunctor as Bifunctor
import           Data.Functor.Classes
import           Data.Functor.Compose
                 ( Compose (..) )
import           Data.Functor.Const
                 ( Const )
import           Data.Functor.Foldable
                 ( Base, Corecursive, Recursive )
import qualified Data.Functor.Foldable as Recursive
import           Data.Functor.Identity
                 ( Identity (..) )
import           Data.Hashable
                 ( Hashable (..) )
import           Data.Maybe
import           Data.Text
                 ( Text )
import           Data.Void
                 ( Void )
import           GHC.Generics
                 ( Generic )

import           Kore.Annotation.Valid
                 ( Valid (..) )
import           Kore.AST.Common hiding
                 ( castVoidDomainValues, mapDomainValues, mapVariables,
                 traverseVariables )
import qualified Kore.AST.Common as Head
import qualified Kore.Attribute.Null as Attribute
import           Kore.Syntax
import           Kore.TopBottom
                 ( TopBottom (..) )
import           Kore.Unparser

{- | The abstract syntax of Kore at a fixed level @level@.

@dom@ is the type of domain values; see "Kore.Domain.External" and
"Kore.Domain.Builtin".

@var@ is the family of variable types, parameterized by level.

@ann@ is the type of annotations decorating each node of the abstract syntax
tree. @PurePattern@ is a 'Traversable' 'Comonad' over the type of annotations.

-}
newtype PurePattern
    (domain :: * -> *)
    (variable :: *)
    (annotation :: *)
  =
    PurePattern
        { getPurePattern :: Cofree (Pattern domain variable) annotation }
    deriving (Foldable, Functor, Generic, Traversable)

instance
    ( Eq variable , Eq1 domain, Functor domain ) =>
    Eq (PurePattern domain variable annotation)
  where
    (==) = eqWorker
      where
        eqWorker
            (Recursive.project -> _ :< pat1)
            (Recursive.project -> _ :< pat2)
          =
            liftEq eqWorker pat1 pat2
    {-# INLINE (==) #-}

instance
    ( Ord variable , Ord1 domain, Functor domain ) =>
    Ord (PurePattern domain variable annotation)
  where
    compare = compareWorker
      where
        compareWorker
            (Recursive.project -> _ :< pat1)
            (Recursive.project -> _ :< pat2)
          =
            liftCompare compareWorker pat1 pat2
    {-# INLINE compare #-}

deriving instance
    ( Show annotation
    , Show variable
    , Show1 domain
    , child ~ Cofree (Pattern domain variable) annotation
    ) =>
    Show (PurePattern domain variable annotation)

instance
    ( Functor domain
    , Hashable variable
    , Hashable (domain child)
    , child ~ PurePattern domain variable annotation
    ) =>
    Hashable (PurePattern domain variable annotation)
  where
    hashWithSalt salt (Recursive.project -> _ :< pat) = hashWithSalt salt pat
    {-# INLINE hashWithSalt #-}

instance
    ( Functor domain
    , NFData annotation
    , NFData variable
    , NFData (domain child)
    , child ~ PurePattern domain variable annotation
    ) =>
    NFData (PurePattern domain variable annotation)
  where
    rnf (Recursive.project -> annotation :< pat) =
        rnf annotation `seq` rnf pat `seq` ()

instance
    ( Functor domain
    , Unparse variable
    , Unparse (domain self)
    , self ~ PurePattern domain variable annotation
    ) =>
    Unparse (PurePattern domain variable annotation)
  where
    unparse (Recursive.project -> _ :< pat) = unparse pat
    unparse2 (Recursive.project -> _ :< pat) = unparse2 pat


type instance Base (PurePattern domain variable annotation) =
    CofreeF (Pattern domain variable) annotation

-- This instance implements all class functions for the PurePattern newtype
-- because the their implementations for the inner type may be specialized.
instance
    Functor domain =>
    Recursive (PurePattern domain variable annotation)
  where
    project = \(PurePattern embedded) ->
        case Recursive.project embedded of
            Compose (Identity projected) -> PurePattern <$> projected
    {-# INLINE project #-}

    -- This specialization is particularly important: The default implementation
    -- of 'cata' in terms of 'project' would involve an extra call to 'fmap' at
    -- every level of the tree due to the implementation of 'project' above.
    cata alg = \(PurePattern fixed) ->
        Recursive.cata
            (\(Compose (Identity base)) -> alg base)
            fixed
    {-# INLINE cata #-}

    para alg = \(PurePattern fixed) ->
        Recursive.para
            (\(Compose (Identity base)) ->
                 alg (Bifunctor.first PurePattern <$> base)
            )
            fixed
    {-# INLINE para #-}

    gpara dist alg = \(PurePattern fixed) ->
        Recursive.gpara
            (\(Compose (Identity base)) -> Compose . Identity <$> dist base)
            (\(Compose (Identity base)) -> alg (Env.local PurePattern <$> base))
            fixed
    {-# INLINE gpara #-}

    prepro pre alg = \(PurePattern fixed) ->
        Recursive.prepro
            (\(Compose (Identity base)) -> (Compose . Identity) (pre base))
            (\(Compose (Identity base)) -> alg base)
            fixed
    {-# INLINE prepro #-}

    gprepro dist pre alg = \(PurePattern fixed) ->
        Recursive.gprepro
            (\(Compose (Identity base)) -> Compose . Identity <$> dist base)
            (\(Compose (Identity base)) -> (Compose . Identity) (pre base))
            (\(Compose (Identity base)) -> alg base)
            fixed
    {-# INLINE gprepro #-}

-- This instance implements all class functions for the PurePattern newtype
-- because the their implementations for the inner type may be specialized.
instance
    Functor domain =>
    Corecursive (PurePattern domain variable annotation)
  where
    embed = \projected ->
        (PurePattern . Recursive.embed . Compose . Identity)
            (getPurePattern <$> projected)
    {-# INLINE embed #-}

    ana coalg = PurePattern . ana0
      where
        ana0 =
            Recursive.ana (Compose . Identity . coalg)
    {-# INLINE ana #-}

    apo coalg = PurePattern . apo0
      where
        apo0 =
            Recursive.apo
                (\a ->
                     (Compose . Identity)
                        (Bifunctor.first getPurePattern <$> coalg a)
                )
    {-# INLINE apo #-}

    postpro post coalg = PurePattern . postpro0
      where
        postpro0 =
            Recursive.postpro
                (\(Compose (Identity base)) -> (Compose . Identity) (post base))
                (Compose . Identity . coalg)
    {-# INLINE postpro #-}

    gpostpro dist post coalg = PurePattern . gpostpro0
      where
        gpostpro0 =
            Recursive.gpostpro
                (Compose . Identity . dist . (<$>) (runIdentity . getCompose))
                (\(Compose (Identity base)) -> (Compose . Identity) (post base))
                (Compose . Identity . coalg)
    {-# INLINE gpostpro #-}

-- This instance implements all class functions for the PurePattern newtype
-- because the their implementations for the inner type may be specialized.
instance
    Functor domain =>
    Comonad (PurePattern domain variable)
  where
    extract = \(PurePattern fixed) -> extract fixed
    {-# INLINE extract #-}
    duplicate = \(PurePattern fixed) -> PurePattern (extend PurePattern fixed)
    {-# INLINE duplicate #-}
    extend extending = \(PurePattern fixed) ->
        PurePattern (extend (extending . PurePattern) fixed)
    {-# INLINE extend #-}

instance
    Functor domain =>
    ComonadCofree
        (Pattern domain variable)
        (PurePattern domain variable)
  where
    unwrap = \(PurePattern fixed) -> PurePattern <$> unwrap fixed
    {-# INLINE unwrap #-}

instance Functor domain
    => TopBottom (PurePattern domain variable annotation)
  where
    isTop (Recursive.project -> _ :< TopPattern Top {}) = True
    isTop _ = False
    isBottom (Recursive.project -> _ :< BottomPattern Bottom {}) = True
    isBottom _ = False

fromPurePattern
    :: Functor domain
    => PurePattern domain variable annotation
    -> Base
        (PurePattern domain variable annotation)
        (PurePattern domain variable annotation)
fromPurePattern = Recursive.project

asPurePattern
    :: Functor domain
    => Base
        (PurePattern domain variable annotation)
        (PurePattern domain variable annotation)
    -> PurePattern domain variable annotation
asPurePattern = Recursive.embed

-- | Erase the annotations from any 'PurePattern'.
eraseAnnotations
    :: Functor domain
    => PurePattern domain variable erased
    -> PurePattern domain variable Attribute.Null
eraseAnnotations = (<$) Attribute.Null

-- | A pure pattern at level @level@ with variables in the common 'Variable'.
type CommonPurePattern domain = PurePattern domain Variable Attribute.Null

-- | A concrete pure pattern (containing no variables) at level @level@.
type ConcretePurePattern domain = PurePattern domain Concrete (Valid Concrete)

-- | A pure pattern which has been parsed and verified.
type VerifiedPurePattern domain = PurePattern domain Variable (Valid Variable)

{- | Use the provided traversal to replace all variables in a 'PurePattern'.

@traverseVariables@ is strict, i.e. its argument is fully evaluated before it
returns. When composing multiple transformations with @traverseVariables@, the
intermediate trees will be fully allocated; @mapVariables@ is more composable in
this respect.

See also: 'mapVariables'

 -}
traverseVariables
    ::  forall m variable1 variable2 domain annotation.
        (Monad m, Traversable domain)
    => (variable1 -> m variable2)
    -> PurePattern domain variable1 annotation
    -> m (PurePattern domain variable2 annotation)
traverseVariables traversing =
    Recursive.fold traverseVariablesWorker
  where
    traverseVariablesWorker
        :: Base
            (PurePattern domain variable1 annotation)
            (m (PurePattern domain variable2 annotation))
        -> m (PurePattern domain variable2 annotation)
    traverseVariablesWorker (a :< pat) =
        reannotate <$> (Head.traverseVariables traversing =<< sequence pat)
      where
        reannotate pat' = Recursive.embed (a :< pat')

{- | Use the provided mapping to replace all variables in a 'PurePattern'.

@mapVariables@ is lazy: it descends into its argument only as the result is
demanded. Intermediate allocation from composing multiple transformations with
@mapVariables@ is amortized; the intermediate trees are never fully resident.

See also: 'traverseVariables'

 -}
mapVariables
    :: Functor domain
    => (variable1 -> variable2)
    -> PurePattern domain variable1 annotation
    -> PurePattern domain variable2 annotation
mapVariables mapping =
    Recursive.ana (mapVariablesWorker . Recursive.project)
  where
    mapVariablesWorker (a :< pat) =
        a :< Head.mapVariables mapping pat

-- | Use the provided mapping to replace all domain values in a 'PurePattern'.
mapDomainValues
    ::  forall domain1 domain2 variable annotation.
        (Functor domain1, Functor domain2)
    => (forall child. domain1 child -> domain2 child)
    -> PurePattern domain1 variable annotation
    -> PurePattern domain2 variable annotation
mapDomainValues mapping =
    -- Using 'Recursive.unfold' so that the pattern will unfold lazily.
    -- Lazy unfolding allows composing multiple tree transformations without
    -- allocating the entire intermediates.
    Recursive.unfold (mapDomainValuesWorker . Recursive.project)
  where
    mapDomainValuesWorker (a :< pat) =
        a :< Head.mapDomainValues mapping pat

{- | Construct a 'ConcretePurePattern' from a 'PurePattern'.

A concrete pattern contains no variables, so @asConcretePurePattern@ is
fully polymorphic on the variable type in the pure pattern. If the argument
contains any variables, the result is @Nothing@.

@asConcretePurePattern@ is strict, i.e. it traverses its argument entirely,
because the entire tree must be traversed to inspect for variables before
deciding if the result is @Nothing@ or @Just _@.

 -}
asConcretePurePattern
    :: forall domain variable annotation . Traversable domain
    => PurePattern domain variable annotation
    -> Maybe (PurePattern domain Concrete annotation)
asConcretePurePattern = traverseVariables (\case { _ -> Nothing })

isConcrete
    :: forall domain variable annotation . Traversable domain
    => PurePattern domain variable annotation
    -> Bool
isConcrete = isJust . asConcretePurePattern

{- | Construct a 'PurePattern' from a 'ConcretePurePattern'.

The concrete pattern contains no variables, so the result is fully
polymorphic in the variable type.

@fromConcretePurePattern@ unfolds the resulting syntax tree lazily, so it
composes with other tree transformations without allocating intermediates.

 -}
fromConcretePurePattern
    :: forall domain variable annotation. Functor domain
    => PurePattern domain Concrete annotation
    -> PurePattern domain variable annotation
fromConcretePurePattern = mapVariables (\case {})

{- | Cast a pure pattern with @'Const' 'Void'@ domain values into any domain.

The @Const Void@ domain excludes domain values; the pattern head be cast
trivially because it must contain no domain values.

 -}
castVoidDomainValues
    :: Functor domain
    => PurePattern (Const Void) variable annotation
    -> PurePattern domain variable annotation
castVoidDomainValues = mapDomainValues (\case {})

-- |Given an 'Id', 'groundHead' produces the head of an 'Application'
-- corresponding to that argument.
groundHead :: Text -> AstLocation -> SymbolOrAlias
groundHead ctor location = SymbolOrAlias
    { symbolOrAliasConstructor = Id
        { getId = ctor
        , idLocation = location
        }
    , symbolOrAliasParams = []
    }

-- |Given a head and a list of children, produces an 'ApplicationPattern'
--  applying the given head to the children
apply :: SymbolOrAlias -> [child] -> Pattern domain variable child
apply patternHead patterns = ApplicationPattern Application
    { applicationSymbolOrAlias = patternHead
    , applicationChildren = patterns
    }

-- |Applies the given head to the empty list of children to obtain a
-- constant 'ApplicationPattern'
constant
    :: SymbolOrAlias -> Pattern domain variable child
constant patternHead = apply patternHead []

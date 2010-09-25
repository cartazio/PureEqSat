{-# LANGUAGE PackageImports #-}
module Opt 
    ( OptMonad
    , D.EqRepr
--    , Rule(..)
--    , MetaData(..)
--    , Result(..)
    , makeClass
    , equivalent -- :: EqRepr       -> EqRepr m -> m Bool
    , union      -- :: EqRepr       -> EqRepr m -> m (EqRepr m)
    , getElems   -- :: EqRepr                   -> m [EqElem m]
    , addElem
    , getClass   -- :: Eq (EqElem m) => EqElem m -> m (Maybe (EqRepr m))
    , getClasses
    , getDependOnMe
    , runOpt -- :: m a -> a
--    , markDirty
--   , isDirty
--    , setShouldNotApply
--    , resetClass
--    , shouldApply
    , dependOn
    , getDepth
    , updated
    , nubClasses
    , getPtr
    , root
  --  , addRule
  --  , addRules
  --  , getTopRule
  --  , getRules
    ) where

import Data.Foldable (toList)
import qualified IOSetA as D -- för att kunna ha samma namn fast lifted
import Control.Monad
import "mtl" Control.Monad.State.Strict
import qualified Data.Map as M
import qualified Data.Sequence as Q -- har O(1) cons och snoc, pa Seq
import qualified Data.Set as S

-- data Rule eqElem = Rule MetaData (D.EqRepr -> eqElem -> OptMonad eqElem Result)
-- Map ID (Map Axiom Bool)
-- Map Axiom (Map ID Bool) <-- tror jag, för vi applicerar samma axiom över flera klasser
-- vilket ar bast? sure, vi later axiom vara typ en int vart i listan over relger det ar eller nagot sant...  fast vi har inte tillgang till Rules har
-- carp circulare import hade varit nice, är en post på cafe om det just nu, kanske de kan fixa det. hade varit skont.

type Axiom = Int -- Depth
--type RuleBitMask = M.Map Axiom (M.Map D.EqRepr Bool)
--type RuleBitMask s = M.Map (D.EqRepr s) (S.Set Axiom)
type RuleBitMask s = M.Map (D.EqRepr s)  Axiom

type OptMonad eqElem = StateT (RuleBitMask eqElem) (D.EqMonad eqElem)

runOpt :: OptMonad s a -> IO a
runOpt o = D.runEqClass (evalStateT o M.empty)

makeClass x = lift (D.makeClass x)
equivalent x y = lift (D.equivalent x y)
--union x y = lift (D.union x y) >>= \s -> resetClass s >> return s
getElems x = lift (D.getElems x) 
getClass x = lift (D.getClass x)
getClasses :: OptMonad eqElem [D.EqRepr eqElem]
getClasses = lift D.getClasses
updated x y = lift(D.updated x y)
getDepth x = lift (D.getDepth x)
nubClasses xs = lift (D.nubClasses xs)
root x = lift (D.root x)
dependOn x xs = lift (D.dependOn x xs)
getDependOnMe x = lift (D.getDependOnMe x)

addElem x cls = do 
    lift (D.addElem x cls)
    deps <- getDependOnMe cls
    fun (S.singleton cls) 1 deps    
    return cls

getPtr rep = lift $ do
    D.Root p _ _ <- D.rootIO rep
    return p

union x y 
  | x == y    = do
    return x -- skulle kunna kolla pekar likhet istället
  | otherwise = do
    b <- equivalent x y
    if b 
        then return x
        else do
            c <- lift (D.union x y) -- >>= \s -> resetClass s >> return s
            deps <- getDependOnMe c
            fun (S.singleton c) 1 deps
            return c 
  
fun :: S.Set (D.EqRepr s) -> Int -> [D.EqRepr s] -> OptMonad s ()
fun set depth [] = return () -- ? mm eller ev return set om vi far problem med loopar har
fun set depth (cls:classes) | cls `S.member` set = fun set depth classes
                            | otherwise = do 
                                updated cls (Just depth) 
                                deps <- getDependOnMe cls
                                fun (S.insert cls set) (depth+1) deps
                                fun (S.insert cls set) depth classes
{-
updateded cls depth = do
    classes <- get
    put $ M.insert cls depth classes


getDepth :: D.EqRepr s -> OptMonad s (Maybe Int)
getDepth rep = do
    classes <- get
    return $ M.lookup rep classes
-}

{-
union x y | x == y    = return x
          | otherwise = lift (D.union x y) >>= \s -> resetClass s >> return s
-}

{-
setShouldNotApply :: Axiom -> D.EqRepr s -> OptMonad s ()
setShouldNotApply ax rep = do 
    classes <- get
    let mq = M.lookup rep classes
    case mq of
        Nothing  -> put $ M.insert rep (S.singleton ax) classes
        Just cls -> put $ M.insert rep (S.insert ax cls) classes

insert key value list = (key,value) : list


resetClass :: D.EqRepr s -> OptMonad s ()
resetClass rep = do
    classes <- get
    put $ M.insert rep S.empty classes

shouldApply :: Axiom -> D.EqRepr s -> OptMonad s Bool
shouldApply ax rep = do
    classes <- get
    let axioms = M.lookup rep classes
    case axioms of
        Nothing -> return True
        Just m  -> return $ not $ S.member ax m
-}

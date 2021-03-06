{-# LANGUAGE OverloadedStrings, ViewPatterns #-}

module Main (
	main
	) where

import Control.Monad (liftM, (>=>))
import Control.Monad.IO.Class
import System.Directory (canonicalizePath)
import System.FilePath (takeExtension)

import HsDev.Error
import HsDev.Inspect (inspectContents, inspectDocs, getDefines)
import HsDev.PackageDb
import HsDev.Project (readProject)
import HsDev.Scan (scanModule, scanModify)
import HsDev.Symbols.Location (ModuleLocation(..))
import HsDev.Tools.Ghc.Types (inferTypes)
import HsDev.Tools.Ghc.Worker
import HsDev.Tools.Ghc.Session (ghcSession)

import Tool

data Opts = Opts (Maybe String) [String]

opts :: Parser Opts
opts = Opts <$>
	optional (strArgument (metavar "what" <> help "depending of what <what> is, inspect installed module, source file (.hs), cabal file (.cabal) or contents, passes as input if no <what> specified")) <*>
	many (strOption (metavar "GHC_OPT" <> long "ghc" <> short 'g' <> help "options to pass to GHC"))

main :: IO ()
main = toolMain "hsinspect" "haskell inspect" opts (runToolClient . inspect') where
	inspect' :: Opts -> ClientM IO Value
	inspect' (Opts Nothing ghcs) = do
		cts <- liftIO getContents
		defs <- liftIO getDefines
		liftM toJSON $ liftIO $ hsdevLift $ inspectContents "stdin" defs ghcs cts
	inspect' (Opts (Just fname@(takeExtension -> ".hs")) ghcs) = do
		fname' <- liftIO $ canonicalizePath fname
		defs <- liftIO getDefines
		im <- scanModule defs ghcs (FileModule fname' Nothing) Nothing
		ghc <- ghcWorker	
		let
			scanAdditional =
				scanModify' (\opts' _ -> liftIO . inspectDocs opts') >=>
				scanModify' (\opts' _ m -> liftIO (inWorker ghc (ghcSession opts' >> inferTypes opts' m Nothing)))
		toJSON <$> scanAdditional im
	inspect' (Opts (Just fcabal@(takeExtension -> ".cabal")) _) = do
		fcabal' <- liftIO $ canonicalizePath fcabal
		toJSON <$> liftIO (readProject fcabal')
	inspect' (Opts (Just mname) ghcs) = toJSON <$> scanModule [] ghcs (InstalledModule UserDb Nothing mname) Nothing
	scanModify' f im = scanModify f im <|> return im

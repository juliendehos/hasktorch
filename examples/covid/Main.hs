{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Main where

import CovidData
import Data.Csv
import qualified Data.Map as M
import Data.Maybe (fromJust)
import qualified Data.Set as S
import Data.Text.Lazy (unpack)
import Data.Time
import qualified Data.Vector as V
import GHC.Generics (Generic)
import qualified Graphics.Vega.VegaLite as VL hiding (sample, shape)
import Pipes
import Pipes.Prelude (drain, toListM)
import Text.Pretty.Simple (pPrint, pShow)
import TimeSeriesModel
import Torch
import Torch as T
import Torch.NN.Recurrent.Cell.LSTM
import Torch.NN.Recurrent.Cell.GRU

plotExampleData modelData tensorData = do
  plotTS (fipsMap modelData) tensorData "25025"
  plotTS (fipsMap modelData) tensorData "51059"
  plotTS (fipsMap modelData) tensorData "48113"
  plotTS (fipsMap modelData) tensorData "06037"
  plotTS (fipsMap modelData) tensorData "06075"

optimSpec initializedModel lossFn =
  OptimSpec
    { optimizer = mkAdam 0 0.9 0.999 (flattenParameters initializedModel),
      batchSize = 1, -- note used ATM
      numIters = 100000,
      -- learningRate = 1e-11, -- LSTM
      learningRate = 1e-3, -- GRU
      lossFn = lossFn
    } ::
    OptimSpec Adam Simple1dModel

modelSpec = Simple1dSpec {
  -- lstm1dSpec = LSTMSpec {inputSize = 1, hiddenSize = 32},
  encoderSpec = MLPEncoder (MLPSpec 1 16 8 1),
  gru1dSpec = GRUSpec {inputSize = 1, hiddenSize = 1},
  decoderSpec = (MLPSpec 1 32 16 1)
}

main :: IO ()
main = do
  putStrLn "Loading Data"
  dataset <- loadDataset "data/us-counties.csv"
  putStrLn "Preprocessing Data"
  modelData <- prepData dataset
  let tensorData = prepTensors modelData

  -- plotExampleData modelData tensorData

  let tIndices = asTensor (fipsIdxs modelData)
      embedDim = 2
  weights <- randnIO' [M.size $ fipsMap modelData, 2]
  let locEmbed = embedding' weights tIndices
  -- print $ indexSelect' 0 [0 .. 10] locEmbed

  -- define fipsSpace
  let fipsList = M.keys . fipsMap $ modelData
  putStrLn "Number of counties:"
  print $ length fipsList

  -- let smallData = filterOn tFips (eq 1223) tensorData
  let smallData = filterOn tFips (eq 0) tensorData
      cases = newCases (tCases smallData)
      tsData = expandToSplits 1 cases
  print (shape cases)
  (model :: Simple1dModel) <- sample modelSpec
  let input = ones' [1, 1]

  -- test data loading and inference
  let (past, future) = getItem tsData 100 1
  let output = forward model (getObs' 0 past)
  print output
  print $ mseLoss (getTime' 0 0 future) output

  -- train model
  trained <- train (optimSpec model mseLoss) tsData model

  putStrLn "Done"

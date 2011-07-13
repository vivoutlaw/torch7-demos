----------------------------------------------------------------------
-- A simple script that trains a conv net on the MNIST dataset,
-- using stochastic gradient descent.
--
-- This script demonstrates a classical example of training a simple
-- convolutional network on a binary classification problem. It
-- illustrates several points:
-- 1/ description of the network
-- 2/ choice of a cost function (criterion) to minimize
-- 3/ instantiation of a trainer, with definition of learning rate, 
--    decays, and momentums
-- 4/ creation of a dataset, from multiple directories of PNGs
-- 5/ running the trainer, which consists in showing all PNGs+Labels
--    to the network, and performing stochastic gradient descent 
--    updates
--
-- Clement Farabet, Benoit Corda  |  July  7, 2011, 12:45PM
----------------------------------------------------------------------

require 'xlua'
xrequire ('image', true)
xrequire ('nnx', true)

----------------------------------------------------------------------
-- parse options
--
op = xlua.OptionParser('%prog [options]')
op:option{'-s', '--save', action='store', dest='save', 
          default='scratch/face-net',
          help='file to save network after each epoch'}
op:option{'-l', '--load', action='store', dest='load',
          help='reload pretrained network'}
op:option{'-d', '--dataset', action='store', dest='dataset', 
          default='../datasets/faces_cut_yuv_32x32/',
          help='path to MNIST root dir'}
op:option{'-w', '--www', action='store', dest='www', 
          default='http://data.neuflow.org/data/faces_cut_yuv_32x32.tar.gz',
          help='path to retrieve dataset online (if not available locally)'}
op:option{'-t', '--testset', action='store', dest='ratio', 
          help='percentage of samples to use for testing', default=0.2}
op:option{'-p', '--patches', action='store', dest='patches', default='all',
          help='nb of patches to use'}
op:option{'-v', '--visualize', action='store_true', dest='visualize',
          help='visualize the datasets'}
opt = op:parse()

torch.setdefaulttensortype('torch.DoubleTensor')

----------------------------------------------------------------------
-- define network to train: CSCF
--
if not opt.network then
   convnet = nn.Sequential()
   convnet:add(nn.SpatialNormalization(1, image.gaussian(7)))
   convnet:add(nn.SpatialConvolution(1, 8, 5, 5))
   convnet:add(nn.Tanh())
   convnet:add(nn.SpatialMaxPooling(4, 4))
   convnet:add(nn.Tanh())
   convnet:add(nn.SpatialConvolution(8, 20, 7, 7))
   convnet:add(nn.Tanh())
   convnet:add(nn.SpatialLinear(20,2))
else
   print('<trainer> reloading previously trained network')
   file = torch.DiskFile(opt.network)
   convnet = nn.Sequential():read(file)
   file:close()
end

----------------------------------------------------------------------
-- training criterion: a simple Mean-Square Error
--
criterion = nn.MSECriterion()
criterion.sizeAverage = true

----------------------------------------------------------------------
-- trainer and hooks
--
trainer = nn.StochasticTrainer{module=convnet, 
                               criterion=criterion,
                               learningRate = 1e-3,
                               learningRateDecay = 1e-2,
                               weightDecay = 1e-5,
                               maxEpoch = 50,
                               momentum = 0.5,
                               save = opt.save}
trainer:setShuffle(false)

confusion = nn.ConfusionMatrix(2, {'Faces', 'Background'})

trainer.hookTrainSample = function(trainer, sample)
   confusion:add(trainer.module.output, sample[2])
end

trainer.hookTestSample = function(trainer, sample)
   confusion:add(trainer.module.output, sample[2])
end

trainer.hookTrainEpoch = function(trainer)
   -- print confusion
   print(confusion)
   confusion:zero()

   -- run on test_set
   trainer:test(testData)

   -- print confusion
   print(confusion)
   confusion:zero()
end

----------------------------------------------------------------------
-- create dataset
--
if not sys.dirp(opt.dataset) then
   local path = sys.dirname(path_dataset)
   local tar = sys.basename(opt.www)
   os.execute('mkdir -p ' .. path .. '; '..
              'cd ' .. path .. '; '..
              'wget ' .. opt.www .. '; '..
              'tar xvf ' .. tar)
end

if opt.patches ~= 'all' then
   opt.patches = math.floor(opt.patches/3)
end

-- Faces:
dataFace = nn.DataSet{dataSetFolder=opt.dataset..'face', 
                      cacheFile=opt.dataset..'face',
                      nbSamplesRequired=opt.patches,
                      channels=1}
dataFace:shuffle()

-- Backgrounds:
dataBG = nn.DataSet{dataSetFolder=opt.dataset..'bg',
                    cacheFile=opt.dataset..'bg',
                    nbSamplesRequired=opt.patches,
                    channels=1}
dataBGext = nn.DataSet{dataSetFolder=opt.dataset..'bg-false-pos-interior-scene',
                       cacheFile=opt.dataset..'bg-false-pos-interior-scene',
                       nbSamplesRequired=opt.patches,
                       channels=1}
dataBG:appendDataSet(dataBGext)
dataBG:shuffle()

-- pop subset for testing
testFace = dataFace:popSubset{ratio=opt.ratio}
testBg = dataBG:popSubset{ratio=opt.ratio}

-- training set
trainData = nn.DataList()
trainData:appendDataSet(dataFace,'Faces')
trainData:appendDataSet(dataBG,'Background')

-- testing set
testData = nn.DataList()
testData:appendDataSet(testFace,'Faces')
testData:appendDataSet(testBg,'Background')

-- display
if opt.visualize then
   trainData:display(100,'trainData')
   testData:display(100,'testData')
end

----------------------------------------------------------------------
-- and train !!
--
trainer:train(trainData)
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": 21,
   "metadata": {},
   "outputs": [
    {
     "name": "stdout",
     "output_type": "stream",
     "text": [
      "[nltk_data] Downloading package punkt to /home/hb1500/nltk_data...\n",
      "[nltk_data]   Unzipping tokenizers/punkt.zip.\n"
     ]
    }
   ],
   "source": [
    "import pandas as pd\n",
    "import numpy as np\n",
    "import torch\n",
    "import torch.nn as nn\n",
    "import torch.nn.functional as F\n",
    "from torch.utils.data import Dataset\n",
    "from torch.autograd import Variable\n",
    "import string\n",
    "import pickle as pkl\n",
    "import random\n",
    "import pdb\n",
    "import re\n",
    "from functools import partial\n",
    "from collections import Counter, defaultdict\n",
    "from sklearn.model_selection import train_test_split\n",
    "from sklearn.model_selection import KFold\n",
    "from sklearn.metrics import roc_auc_score\n",
    "import nltk\n",
    "from nltk.tokenize import word_tokenize\n",
    "from nltk.corpus import stopwords\n",
    "nltk.download('punkt')\n",
    "from gensim.models.keyedvectors import KeyedVectors\n",
    "import matplotlib.pyplot as plt\n",
    "\n",
    "RANDOM_STATE = 42"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "### Get pre-trained embeddings"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 11,
   "metadata": {},
   "outputs": [],
   "source": [
    "# emcode the pretrained embedding to text file\n",
    "model = KeyedVectors.load_word2vec_format('/home/hb1500/Plated/vocab.bin', binary=True)\n",
    "model.save_word2vec_format('pretrained_embd.txt', binary=False)"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 59,
   "metadata": {},
   "outputs": [],
   "source": [
    "# load embeddings\n",
    "# There are three types of embeddings: \n",
    "# pretrained_embd (from Recipe101); pretrained_embd (Recipe101 + Plated); Glove.6B.50d\n",
    "def load_emb_vectors(fname):\n",
    "    data = {}\n",
    "    with open(fname, 'r') as f:\n",
    "        for line in f:\n",
    "            splitLine = line.split()\n",
    "            word = splitLine[0]\n",
    "            embedding = np.array([float(val) for val in splitLine[1:]])\n",
    "            data[word] = embedding\n",
    "    return data\n",
    "#fname = 'pretrained_embd.txt'\n",
    "#fname = '/Users/hetianbai/Desktop/DS-GA 1011/Labs/lab5/glove.6B/glove.6B.50d.txt'\n",
    "fname = '/scratch/hb1500/Plated/glove.6B/glove.6B.50d.txt'\n",
    "words_emb_dict = load_emb_vectors(fname)"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "### Load Cleaned Data "
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 108,
   "metadata": {},
   "outputs": [],
   "source": [
    "# the data is the output of \"Consolidated Data Cleaning\"\n",
    "data_all = pd.read_csv('cleaned_recipe_data.csv', index_col=0)"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 109,
   "metadata": {},
   "outputs": [],
   "source": [
    "data_intruction = data_all[['external_id','step_one','step_two', 'step_three', 'step_four', 'step_five', 'step_six']]"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 110,
   "metadata": {},
   "outputs": [],
   "source": [
    "data_cuisine_tags = data_all[['external_id','tag_cuisine_indian', 'tag_cuisine_nordic', 'tag_cuisine_european',\n",
    "       'tag_cuisine_asian', 'tag_cuisine_mexican',\n",
    "       'tag_cuisine_latin-american', 'tag_cuisine_french',\n",
    "       'tag_cuisine_italian', 'tag_cuisine_african',\n",
    "       'tag_cuisine_mediterranean', 'tag_cuisine_american',\n",
    "       'tag_cuisine_middle-eastern']]"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "### Tokenization"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 111,
   "metadata": {},
   "outputs": [],
   "source": [
    "# lowercase and remove punctuation\n",
    "def tokenizer(sent):\n",
    "    #print(sent)\n",
    "    if pd.isnull(sent):\n",
    "        words = []\n",
    "    else:\n",
    "        table = str.maketrans(string.punctuation, ' '*len(string.punctuation))\n",
    "        sent = sent.translate(table)\n",
    "        tokens = word_tokenize(sent)\n",
    "        # convert to lower case\n",
    "        tokens = [w.lower() for w in tokens]\n",
    "        # remove punctuation from each word\n",
    "        #table = str.maketrans('', '', string.punctuation)\n",
    "        #stripped = [w.translate(table) for w in tokens]\n",
    "        # remove remaining tokens that are not alphabetic\n",
    "        words = [word for word in tokens if word.isalpha()]\n",
    "        #re.findall(r'\\d+', 'sdfa')\n",
    "    return words"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 112,
   "metadata": {},
   "outputs": [],
   "source": [
    "def tokenize_dataset(step_n):\n",
    "    \"\"\"returns tokenization for each step, training set tokenizatoin\"\"\"\n",
    "    token_dataset = []\n",
    "    for sample in step_n:\n",
    "        tokens = tokenizer(sample)\n",
    "        token_dataset.append(tokens)\n",
    "    return token_dataset\n",
    "\n",
    "def all_tokens_list(train_data):\n",
    "    \"\"\"returns all tokens of instruction (all steps) for creating vocabulary\"\"\"\n",
    "    all_tokens = []\n",
    "    for columns in train_data.columns[1:]:\n",
    "        for sample in train_data[columns]:\n",
    "            all_tokens += sample[:] \n",
    "    return all_tokens"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 113,
   "metadata": {},
   "outputs": [
    {
     "name": "stdout",
     "output_type": "stream",
     "text": [
      "step_one has been tokenized.\n",
      "step_two has been tokenized.\n",
      "step_three has been tokenized.\n",
      "step_four has been tokenized.\n",
      "step_five has been tokenized.\n",
      "step_six has been tokenized.\n"
     ]
    }
   ],
   "source": [
    "# tokenize each steps\n",
    "data_instruction_tokenized = pd.DataFrame()\n",
    "for steps in data_intruction.columns[1:]:\n",
    "    data_instruction_tokenized[steps] = tokenize_dataset(data_intruction[steps])\n",
    "    print(steps, 'has been tokenized.')\n",
    "data_instruction_tokenized['external_id'] = data_intruction['external_id']"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 114,
   "metadata": {},
   "outputs": [],
   "source": [
    "assert (data_instruction_tokenized.shape[0] == data_cuisine_tags.shape[0])"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 115,
   "metadata": {},
   "outputs": [],
   "source": [
    "# add tags to tokenized dataframe\n",
    "data_instruction_tokenized = data_instruction_tokenized.merge(data_cuisine_tags, on = 'external_id')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 116,
   "metadata": {},
   "outputs": [],
   "source": [
    "# data_instruction_tokenized.to_csv('data_instruction_tokenized')"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "Naming two dataframes: one for intructions (with id) and the other for tags (with id)"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 117,
   "metadata": {},
   "outputs": [],
   "source": [
    "data_intruction = data_instruction_tokenized[['external_id','step_one','step_two', 'step_three', 'step_four', 'step_five', 'step_six']]\n",
    "data_tags = data_instruction_tokenized[['external_id','tag_cuisine_indian', 'tag_cuisine_nordic', 'tag_cuisine_european',\n",
    "       'tag_cuisine_asian', 'tag_cuisine_mexican',\n",
    "       'tag_cuisine_latin-american', 'tag_cuisine_french',\n",
    "       'tag_cuisine_italian', 'tag_cuisine_african',\n",
    "       'tag_cuisine_mediterranean', 'tag_cuisine_american',\n",
    "       'tag_cuisine_middle-eastern']]"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "Split train and test sets"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 120,
   "metadata": {},
   "outputs": [],
   "source": [
    "X_train, test_data, y_train, test_tags = train_test_split(data_intruction, data_tags, test_size=0.1, random_state=RANDOM_STATE)\n",
    "#train_data, val_data, train_tags, val_tags = train_test_split(X_train, y_train, test_size=0.1, random_state=RANDOM_STATE)"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "Cross validation for train and validation "
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 103,
   "metadata": {},
   "outputs": [
    {
     "name": "stdout",
     "output_type": "stream",
     "text": [
      "===================== This is the Kfold 1 =====================\n",
      "The number of train parameters 7711\n",
      "1/5, Step:1/36, TrainLoss:0.826720, ValAUC:0.480010 ValAcc:0.701357\n",
      "1/5, Step:11/36, TrainLoss:0.620266, ValAUC:0.538099 ValAcc:0.701357\n",
      "1/5, Step:21/36, TrainLoss:0.630199, ValAUC:0.533456 ValAcc:0.701357\n",
      "1/5, Step:31/36, TrainLoss:0.724640, ValAUC:0.528128 ValAcc:0.701357\n",
      "Epoch: [1/5], trainAUC: 0.584496, trainAcc: 0.731597\n",
      "Epoch: [1/5], ValAUC: 0.519208, ValAcc: 0.701357\n",
      "2/5, Step:1/36, TrainLoss:0.548948, ValAUC:0.519062 ValAcc:0.701357\n",
      "2/5, Step:11/36, TrainLoss:0.678525, ValAUC:0.522483 ValAcc:0.701357\n",
      "2/5, Step:21/36, TrainLoss:0.528223, ValAUC:0.533920 ValAcc:0.701357\n",
      "2/5, Step:31/36, TrainLoss:0.515556, ValAUC:0.533431 ValAcc:0.701357\n",
      "Epoch: [2/5], trainAUC: 0.615599, trainAcc: 0.731597\n",
      "Epoch: [2/5], ValAUC: 0.535386, ValAcc: 0.701357\n",
      "3/5, Step:1/36, TrainLoss:0.499553, ValAUC:0.528055 ValAcc:0.701357\n",
      "3/5, Step:11/36, TrainLoss:0.636912, ValAUC:0.531232 ValAcc:0.701357\n",
      "3/5, Step:21/36, TrainLoss:0.572826, ValAUC:0.526369 ValAcc:0.699535\n",
      "3/5, Step:31/36, TrainLoss:0.512027, ValAUC:0.564541 ValAcc:0.701357\n",
      "Epoch: [3/5], trainAUC: 0.621608, trainAcc: 0.731597\n",
      "Epoch: [3/5], ValAUC: 0.569086, ValAcc: 0.701357\n",
      "4/5, Step:1/36, TrainLoss:0.516010, ValAUC:0.561168 ValAcc:0.701357\n",
      "4/5, Step:11/36, TrainLoss:0.586636, ValAUC:0.580108 ValAcc:0.701357\n",
      "4/5, Step:21/36, TrainLoss:0.456879, ValAUC:0.565078 ValAcc:0.701357\n",
      "4/5, Step:31/36, TrainLoss:0.561752, ValAUC:0.578446 ValAcc:0.701357\n",
      "Epoch: [4/5], trainAUC: 0.644985, trainAcc: 0.731597\n",
      "Epoch: [4/5], ValAUC: 0.561413, ValAcc: 0.701357\n",
      "5/5, Step:1/36, TrainLoss:0.458574, ValAUC:0.563074 ValAcc:0.701357\n",
      "5/5, Step:11/36, TrainLoss:0.666838, ValAUC:0.544477 ValAcc:0.700446\n",
      "5/5, Step:21/36, TrainLoss:0.507187, ValAUC:0.569110 ValAcc:0.701357\n",
      "5/5, Step:31/36, TrainLoss:0.722205, ValAUC:0.549939 ValAcc:0.701357\n",
      "Epoch: [5/5], trainAUC: 0.672277, trainAcc: 0.731335\n",
      "Epoch: [5/5], ValAUC: 0.547923, ValAcc: 0.701357\n"
     ]
    }
   ],
   "source": [
    "kf = KFold(n_splits=5, shuffle=False, random_state=RANDOM_STATE)\n",
    "k = 1\n",
    "for train_index, val_index in kf.split(X_train):\n",
    "    print('===================== This is the Kfold {} ====================='.format(k))\n",
    "    k += 1\n",
    "    train_data, val_data = X_train.iloc[train_index], X_train.iloc[val_index] \n",
    "    train_tags, val_tags = y_train.iloc[train_index], y_train.iloc[val_index]\n",
    "    # lookup table\n",
    "    all_train_tokens = all_tokens_list(train_data)\n",
    "    max_vocab_size = len(list(set(all_train_tokens)))\n",
    "    token2id, id2token = build_vocab(all_train_tokens, max_vocab_size)\n",
    "    random_token_id = random.randint(0, len(id2token)-1)\n",
    "    random_token = id2token[random_token_id]\n",
    "    emb_weight = build_emb_weight(words_emb_dict, id2token)\n",
    "    train_data_indices = token2index_dataset(train_data, token2id)\n",
    "    val_data_indices = token2index_dataset(val_data, token2id)\n",
    "    test_data_indices = token2index_dataset(test_data, token2id)\n",
    "    # batchify datasets: \n",
    "    train_loader, val_loader, test_loader = create_dataset_obj(train_data_indices, val_data_indices,\n",
    "                                                           test_data_indices, train_targets,\n",
    "                                                           val_targets, test_targets,\n",
    "                                                           BATCH_SIZE, max_sent_len, \n",
    "                                                           collate_func)\n",
    "    #load pre-embeddings\n",
    "    weights_matrix = torch.from_numpy(emb_weight)\n",
    "    # define model\n",
    "    model_train(rnn_1,hidden_dim1,bi,rnn_2, hidden_dim2, batch_size, cuda_on, num_classes)\n",
    "    break   "
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    " All tokens from training set"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 121,
   "metadata": {},
   "outputs": [],
   "source": [
    "# form all tokens list\n",
    "all_train_tokens = all_tokens_list(train_data)"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "Let's decide which tag to predict for trail"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {
    "scrolled": false
   },
   "outputs": [],
   "source": [
    "data_cuisine_tags.iloc[:,1:].sum()/data_cuisine_tags.iloc[:,1:].shape[0]"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "Choose tag: tag_cuisine_american, which 27.3525% are 1 "
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "### Build vocabulary and indexing "
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 123,
   "metadata": {},
   "outputs": [
    {
     "data": {
      "text/plain": [
       "3157"
      ]
     },
     "execution_count": 123,
     "metadata": {},
     "output_type": "execute_result"
    }
   ],
   "source": [
    "len(list(set(all_train_tokens)))"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 124,
   "metadata": {},
   "outputs": [],
   "source": [
    "token_counter = Counter(all_train_tokens)\n",
    "# token_counter.most_common"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 125,
   "metadata": {},
   "outputs": [],
   "source": [
    "# save index 0 for unk and 1 for pad\n",
    "def build_vocab(all_tokens, max_vocab_size):\n",
    "    # Returns:\n",
    "    # id2token: list of tokens, where id2token[i] returns token that corresponds to token i\n",
    "    # token2id: dictionary where keys represent tokens and corresponding values represent indices\n",
    "    PAD_IDX = 0\n",
    "    UNK_IDX = 1\n",
    "    token_counter = Counter(all_tokens)\n",
    "    vocab, count = zip(*token_counter.most_common(max_vocab_size))\n",
    "    id2token = list(vocab)\n",
    "    token2id = dict(zip(vocab, range(2,2+len(vocab)))) \n",
    "    id2token = ['<pad>', '<unk>'] + id2token\n",
    "    token2id['<pad>'] = PAD_IDX \n",
    "    token2id['<unk>'] = UNK_IDX\n",
    "    return token2id, id2token"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 126,
   "metadata": {},
   "outputs": [
    {
     "name": "stdout",
     "output_type": "stream",
     "text": [
      "Token id 304 ; token line\n",
      "Token line; token id 304\n"
     ]
    }
   ],
   "source": [
    "max_vocab_size = len(list(set(all_train_tokens)))\n",
    "token2id, id2token = build_vocab(all_train_tokens, max_vocab_size)\n",
    "\n",
    "random_token_id = random.randint(0, len(id2token)-1)\n",
    "random_token = id2token[random_token_id]\n",
    "\n",
    "print(\"Token id {} ; token {}\".format(random_token_id, id2token[random_token_id]))\n",
    "print(\"Token {}; token id {}\".format(random_token, token2id[random_token]))"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 127,
   "metadata": {},
   "outputs": [],
   "source": [
    "def build_emb_weight(words_emb_dict, id2token):\n",
    "    vocab_size = len(id2token)\n",
    "    emb_dim = len(words_emb_dict['a'])\n",
    "    emb_weight = np.zeros([vocab_size, emb_dim])\n",
    "    for i in range(2,vocab_size):\n",
    "        emb = words_emb_dict.get(id2token[i], None)\n",
    "        if emb is not None:\n",
    "            emb_weight[i] = emb\n",
    "    return emb_weight"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 88,
   "metadata": {},
   "outputs": [],
   "source": [
    "emb_weight = build_emb_weight(words_emb_dict, id2token)"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 89,
   "metadata": {},
   "outputs": [
    {
     "data": {
      "text/plain": [
       "0.049302627311060658"
      ]
     },
     "execution_count": 89,
     "metadata": {},
     "output_type": "execute_result"
    }
   ],
   "source": [
    "sum(np.sum(emb_weight,1)==0)/emb_weight.shape[0]"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "Reconstruct data strcuture for datasets"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 128,
   "metadata": {},
   "outputs": [
    {
     "name": "stdout",
     "output_type": "stream",
     "text": [
      "Train dataset size is 1987\n",
      "Val dataset size is 221\n",
      "Test dataset size is 246\n"
     ]
    }
   ],
   "source": [
    "# convert token to id in the dataset\n",
    "def token2index_dataset(tokens_data, token2id):\n",
    "    \"\"\"returns [[[step1 indices],[step2 indices],...,[step6 indices]],[],[],...]\"\"\"\n",
    "    recipie_indices_data = []\n",
    "    UNK_IDX = 1\n",
    "    for recipie in tokens_data.iterrows():\n",
    "        step_indices_data = []\n",
    "        for step in recipie[1]:\n",
    "            index_list = [token2id[token] if token in token2id else UNK_IDX for token in step]\n",
    "            step_indices_data.append(index_list)\n",
    "        recipie_indices_data.append(step_indices_data)\n",
    "    return recipie_indices_data\n",
    "\n",
    "train_data_indices = token2index_dataset(train_data, token2id)\n",
    "val_data_indices = token2index_dataset(val_data, token2id)\n",
    "test_data_indices = token2index_dataset(test_data, token2id)\n",
    "\n",
    "# double checking\n",
    "print (\"Train dataset size is {}\".format(len(train_data_indices)))\n",
    "print (\"Val dataset size is {}\".format(len(val_data_indices)))\n",
    "print (\"Test dataset size is {}\".format(len(test_data_indices)))"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 91,
   "metadata": {},
   "outputs": [],
   "source": [
    "class IntructionDataset(Dataset):\n",
    "    \"\"\"\n",
    "    Class that represents a train/validation/test dataset that's readable for PyTorch\n",
    "    Note that this class inherits torch.utils.data.Dataset\n",
    "    \"\"\"\n",
    "    \n",
    "    def __init__(self, data_list, tags_list, max_sent_len):\n",
    "        \"\"\"\n",
    "        \n",
    "        @param data_list: list of recipie tokens \n",
    "        @param target_list: list of single tag, i.e. 'tag_cuisine_american'\n",
    "\n",
    "        \"\"\"\n",
    "        self.data_list = data_list\n",
    "        self.tags_list = tags_list\n",
    "        assert (len(self.data_list) == len(self.tags_list))\n",
    "\n",
    "    def __len__(self):\n",
    "        return len(self.data_list)\n",
    "        \n",
    "    def __getitem__(self, key):\n",
    "        \"\"\"\n",
    "        Triggered when you call recipie[i]\n",
    "        \"\"\"\n",
    "        recipie = self.data_list[key]\n",
    "        step1_idx = recipie[0][:max_sent_len[0]]\n",
    "        step2_idx = recipie[1][:max_sent_len[1]]\n",
    "        step3_idx = recipie[2][:max_sent_len[2]]\n",
    "        step4_idx = recipie[3][:max_sent_len[3]]       \n",
    "        step5_idx = recipie[4][:max_sent_len[4]]\n",
    "        step6_idx = recipie[5][:max_sent_len[5]]\n",
    "        label = self.tags_list[key]\n",
    "        return [[step1_idx, step2_idx, step3_idx, step4_idx, step5_idx, step6_idx], \n",
    "                [len(step1_idx),len(step2_idx), len(step3_idx),len(step4_idx), len(step5_idx),len(step6_idx)], \n",
    "                label]\n",
    "\n",
    "def collate_func(batch):\n",
    "    \"\"\"\n",
    "    Customized function for DataLoader that dynamically pads the batch so that all \n",
    "    data have the same length\n",
    "    \"\"\"\n",
    "    steps_dict = defaultdict(list)\n",
    "    label_list = []\n",
    "    length_dict = defaultdict(list)\n",
    "    max_sent_len = []\n",
    "    for datum in batch:\n",
    "        label_list.append(datum[-1])\n",
    "        for i in range(6):\n",
    "            length_dict[i].append(datum[1][i])\n",
    "    # padding\n",
    "    for i in range(6):\n",
    "        max_sent_len.append(max(length_dict[i]))\n",
    "    \n",
    "    for datum in batch:\n",
    "        for i, step in enumerate(datum[0]):\n",
    "            padded_vec = np.pad(np.array(step), \n",
    "                                pad_width=((0, max_sent_len[i]-datum[1][i])), \n",
    "                                mode=\"constant\", constant_values=0)\n",
    "            steps_dict[i].append(padded_vec)\n",
    "    \n",
    "    for key in length_dict.keys():\n",
    "        length_dict[key] = torch.LongTensor(length_dict[key])\n",
    "        steps_dict[key] = torch.from_numpy(np.array(steps_dict[key]).astype(np.int)) \n",
    "        \n",
    "    return [steps_dict, length_dict, torch.LongTensor(label_list)]"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 92,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Build train, valid and test dataloaders\n",
    "def create_dataset_obj(train,val,test,train_targets,val_targets,test_targets,\n",
    "                       BATCH_SIZE,max_sent_len,collate_func):\n",
    "    collate_func=partial(collate_func)\n",
    "    train_dataset = IntructionDataset(train, train_targets, max_sent_len)\n",
    "    train_loader = torch.utils.data.DataLoader(dataset=train_dataset,\n",
    "                                               batch_size=BATCH_SIZE,\n",
    "                                               collate_fn=collate_func,\n",
    "                                               shuffle=True)\n",
    "\n",
    "    val_dataset = IntructionDataset(val, val_targets, max_sent_len)\n",
    "    val_loader = torch.utils.data.DataLoader(dataset=val_dataset,\n",
    "                                               batch_size=BATCH_SIZE,\n",
    "                                               collate_fn=collate_func,\n",
    "                                               shuffle=False)\n",
    "\n",
    "    test_dataset = IntructionDataset(test, test_targets, max_sent_len)\n",
    "    test_loader = torch.utils.data.DataLoader(dataset=test_dataset,\n",
    "                                               batch_size=BATCH_SIZE,\n",
    "                                               collate_fn=collate_func,\n",
    "                                               shuffle=False)\n",
    "    return train_loader, val_loader, test_loader"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 93,
   "metadata": {},
   "outputs": [],
   "source": [
    "def create_emb_layer(weights_matrix, trainable=False):\n",
    "    vocab_size, emb_dim = weights_matrix.size()\n",
    "    emb_layer = nn.Embedding(vocab_size, emb_dim)\n",
    "    emb_layer.load_state_dict({'weight': weights_matrix})\n",
    "    if trainable == False:\n",
    "        emb_layer.weight.requires_grad = False\n",
    "    return emb_layer, vocab_size, emb_dim\n",
    "\n",
    "class two_stage_RNN(nn.Module):\n",
    "    def __init__(self, rnn_1, hidden_dim1, bi, rnn_2, hidden_dim2, batch_size, cuda_on, num_classes):\n",
    "        \n",
    "        super(two_stage_RNN, self).__init__()\n",
    "        \n",
    "        self.hidden_dim1 = hidden_dim1\n",
    "        self.hidden_dim2 = hidden_dim2\n",
    "\n",
    "        self.embedding, vocab_size, emb_dim = create_emb_layer(weights_matrix, trainable=False)\n",
    "        \n",
    "        # module for steps in the fisrt stage\n",
    "#         self.hidden_stage1, self.hidden_stage2 = self.init_hidden(batch_size, cuda_on)\n",
    "        rnn_common = rnn_1(emb_dim, hidden_dim1, num_layers=1, \n",
    "                           batch_first=True, bidirectional=bi)\n",
    "        self.rnn_each_step = nn.ModuleList([])\n",
    "        for i in range(6):\n",
    "            self.rnn_each_step.append(rnn_common)\n",
    "        \n",
    "        # module for the second stage\n",
    "        if bi:\n",
    "            self.steps_rnn = rnn_2(hidden_dim1*2, hidden_dim2, num_layers=1, batch_first=False)\n",
    "        else:\n",
    "            self.steps_rnn = rnn_2(hidden_dim1, hidden_dim2, num_layers=1, batch_first=False)\n",
    "        # module for interaction\n",
    "        self.linear = nn.Linear(hidden_dim2, num_classes)\n",
    "        \n",
    "    def forward(self, steps, lengths):\n",
    "        # first stage\n",
    "        output_each_step = []\n",
    "        for i in range(6):\n",
    "            rnn_input = steps[i]\n",
    "            emb = self.embedding(rnn_input) # embedding\n",
    "\n",
    "            output, _ = self.rnn_each_step[i](emb) #, self.hidden_stage1[str(i)]\n",
    "            if bi:\n",
    "                output_size = output.size()\n",
    "                output = output.view(output_size[0], output_size[1], 2, self.hidden_dim1)\n",
    "            if bi:\n",
    "                output_each_step.append(torch.cat((output[:,-1,0,:],output[:,0,1,:]),1))\n",
    "            else:\n",
    "                output_each_step.append(output[:,-1,:])\n",
    "        \n",
    "        #second stage\n",
    "        output1 = torch.stack(output_each_step, 0)\n",
    "        output, _ = self.steps_rnn(output1) #, self.hidden_stage2\n",
    "        logits = self.linear(output[-1,:,:])\n",
    "        #logits = torch.sigmoid(logits)\n",
    "        return logits\n",
    "\n",
    "def test_model(loader, model):\n",
    "    \"\"\"\n",
    "    Help function that tests the model's performance on a dataset\n",
    "    @param: loader - data loader for the dataset to test against\n",
    "    \"\"\"\n",
    "    logits_all = []\n",
    "    labels_all = []\n",
    "    model.eval()\n",
    "    for steps_batch, lengths_batch, labels_batch in loader:\n",
    "        for step_id in range(6):\n",
    "            lengths_batch[step_id] = lengths_batch[step_id].cuda()\n",
    "            steps_batch[step_id] = steps_batch[step_id].cuda() \n",
    "        logits = model(steps_batch, lengths_batch)\n",
    "        logits_all.extend(list(logits.cpu().detach().numpy()))\n",
    "        labels_all.extend(list(labels_batch.numpy()))\n",
    "    logits_all = np.array(logits_all)\n",
    "    labels_all = np.array(labels_all)\n",
    "    auc = roc_auc_score(labels_all, logits_all)\n",
    "    predicts = (logits_all > 0.5).astype(int)\n",
    "    acc = np.mean(predicts==labels_all)\n",
    "    return auc, acc"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "tag_cuisine_indian            0.023525  85% auc\n",
    "tag_cuisine_nordic            0.000399\n",
    "tag_cuisine_european          0.012360\n",
    "tag_cuisine_asian             0.182217  98% auc\n",
    "tag_cuisine_mexican           0.013557\n",
    "tag_cuisine_latin-american    0.094896  90% auc\n",
    "tag_cuisine_french            0.077352  72% auc\n",
    "tag_cuisine_italian           0.233254  80% auc\n",
    "tag_cuisine_african           0.003987\n",
    "tag_cuisine_mediterranean     0.076555  88% auc\n",
    "tag_cuisine_american          0.273525  80% auc\n",
    "tag_cuisine_middle-eastern    0.046252  87% auc"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 129,
   "metadata": {},
   "outputs": [],
   "source": [
    "tag_predicted = 'tag_cuisine_american'\n",
    "train_targets = list(train_tags[tag_predicted])\n",
    "val_targets = list(val_tags[tag_predicted])\n",
    "test_targets = list(test_tags[tag_predicted])"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 95,
   "metadata": {},
   "outputs": [
    {
     "name": "stdout",
     "output_type": "stream",
     "text": [
      "0    1292\n",
      "1     474\n",
      "Name: tag_cuisine_american, dtype: int64\n",
      "0    310\n",
      "1    132\n",
      "Name: tag_cuisine_american, dtype: int64\n",
      "0    180\n",
      "1     66\n",
      "Name: tag_cuisine_american, dtype: int64\n"
     ]
    }
   ],
   "source": [
    "print(train_tags[tag_predicted].value_counts())\n",
    "print(val_tags[tag_predicted].value_counts())\n",
    "print(test_tags[tag_predicted].value_counts())"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 99,
   "metadata": {},
   "outputs": [],
   "source": [
    "rnn_types = {\n",
    "    'rnn': nn.RNN,\n",
    "    'lstm': nn.LSTM,\n",
    "    'gru': nn.GRU\n",
    "}\n",
    "\n",
    "params = dict(\n",
    "    rnn1_type = 'rnn',\n",
    "    rnn2_type = 'rnn',\n",
    "    bi = True,\n",
    "    hidden_dim1 = 30,\n",
    "    hidden_dim2 = 30,\n",
    "    num_classes = 1,\n",
    "    \n",
    "    num_epochs = 5,\n",
    "    batch_size = 50,\n",
    "    learning_rate = 0.01,\n",
    "    cuda_on = True \n",
    ")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 131,
   "metadata": {},
   "outputs": [],
   "source": [
    "BATCH_SIZE = params['batch_size']\n",
    "max_sent_len = np.array([94, 86, 87, 90, 98, 91])\n",
    "\n",
    "train_loader, val_loader, test_loader = create_dataset_obj(train_data_indices, val_data_indices,\n",
    "                                                           test_data_indices, train_targets,\n",
    "                                                           val_targets, test_targets,\n",
    "                                                           BATCH_SIZE, max_sent_len, \n",
    "                                                           collate_func)"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 139,
   "metadata": {},
   "outputs": [
    {
     "name": "stdout",
     "output_type": "stream",
     "text": [
      "The number of train parameters 7711\n"
     ]
    },
    {
     "ename": "RuntimeError",
     "evalue": "cuda runtime error (59) : device-side assert triggered at /pytorch/aten/src/THC/generic/THCTensorCopy.cpp:20",
     "output_type": "error",
     "traceback": [
      "\u001b[0;31m---------------------------------------------------------------------------\u001b[0m",
      "\u001b[0;31mRuntimeError\u001b[0m                              Traceback (most recent call last)",
      "\u001b[0;32m<ipython-input-139-b1c672e1973d>\u001b[0m in \u001b[0;36m<module>\u001b[0;34m()\u001b[0m\n\u001b[1;32m     15\u001b[0m \u001b[0mmodel_parameters\u001b[0m \u001b[0;34m=\u001b[0m \u001b[0mfilter\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0;32mlambda\u001b[0m \u001b[0mp\u001b[0m\u001b[0;34m:\u001b[0m \u001b[0mp\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0mrequires_grad\u001b[0m\u001b[0;34m,\u001b[0m \u001b[0mmodel\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0mparameters\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[1;32m     16\u001b[0m \u001b[0mprint\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0;34m'The number of train parameters'\u001b[0m\u001b[0;34m,\u001b[0m \u001b[0msum\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0;34m[\u001b[0m\u001b[0mnp\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0mprod\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0mp\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0msize\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m)\u001b[0m \u001b[0;32mfor\u001b[0m \u001b[0mp\u001b[0m \u001b[0;32min\u001b[0m \u001b[0mmodel_parameters\u001b[0m\u001b[0;34m]\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[0;32m---> 17\u001b[0;31m \u001b[0mmodel\u001b[0m \u001b[0;34m=\u001b[0m \u001b[0mmodel\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0mcuda\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[0m\u001b[1;32m     18\u001b[0m \u001b[0;34m\u001b[0m\u001b[0m\n\u001b[1;32m     19\u001b[0m \u001b[0;31m#parameter for training\u001b[0m\u001b[0;34m\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n",
      "\u001b[0;32m~/py3.6.3/lib/python3.6/site-packages/torch/nn/modules/module.py\u001b[0m in \u001b[0;36mcuda\u001b[0;34m(self, device)\u001b[0m\n\u001b[1;32m    256\u001b[0m             \u001b[0mModule\u001b[0m\u001b[0;34m:\u001b[0m \u001b[0mself\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[1;32m    257\u001b[0m         \"\"\"\n\u001b[0;32m--> 258\u001b[0;31m         \u001b[0;32mreturn\u001b[0m \u001b[0mself\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0m_apply\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0;32mlambda\u001b[0m \u001b[0mt\u001b[0m\u001b[0;34m:\u001b[0m \u001b[0mt\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0mcuda\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0mdevice\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[0m\u001b[1;32m    259\u001b[0m \u001b[0;34m\u001b[0m\u001b[0m\n\u001b[1;32m    260\u001b[0m     \u001b[0;32mdef\u001b[0m \u001b[0mcpu\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0mself\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m:\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n",
      "\u001b[0;32m~/py3.6.3/lib/python3.6/site-packages/torch/nn/modules/module.py\u001b[0m in \u001b[0;36m_apply\u001b[0;34m(self, fn)\u001b[0m\n\u001b[1;32m    183\u001b[0m     \u001b[0;32mdef\u001b[0m \u001b[0m_apply\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0mself\u001b[0m\u001b[0;34m,\u001b[0m \u001b[0mfn\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m:\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[1;32m    184\u001b[0m         \u001b[0;32mfor\u001b[0m \u001b[0mmodule\u001b[0m \u001b[0;32min\u001b[0m \u001b[0mself\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0mchildren\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m:\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[0;32m--> 185\u001b[0;31m             \u001b[0mmodule\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0m_apply\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0mfn\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[0m\u001b[1;32m    186\u001b[0m \u001b[0;34m\u001b[0m\u001b[0m\n\u001b[1;32m    187\u001b[0m         \u001b[0;32mfor\u001b[0m \u001b[0mparam\u001b[0m \u001b[0;32min\u001b[0m \u001b[0mself\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0m_parameters\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0mvalues\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m:\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n",
      "\u001b[0;32m~/py3.6.3/lib/python3.6/site-packages/torch/nn/modules/module.py\u001b[0m in \u001b[0;36m_apply\u001b[0;34m(self, fn)\u001b[0m\n\u001b[1;32m    189\u001b[0m                 \u001b[0;31m# Tensors stored in modules are graph leaves, and we don't\u001b[0m\u001b[0;34m\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[1;32m    190\u001b[0m                 \u001b[0;31m# want to create copy nodes, so we have to unpack the data.\u001b[0m\u001b[0;34m\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[0;32m--> 191\u001b[0;31m                 \u001b[0mparam\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0mdata\u001b[0m \u001b[0;34m=\u001b[0m \u001b[0mfn\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0mparam\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0mdata\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[0m\u001b[1;32m    192\u001b[0m                 \u001b[0;32mif\u001b[0m \u001b[0mparam\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0m_grad\u001b[0m \u001b[0;32mis\u001b[0m \u001b[0;32mnot\u001b[0m \u001b[0;32mNone\u001b[0m\u001b[0;34m:\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[1;32m    193\u001b[0m                     \u001b[0mparam\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0m_grad\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0mdata\u001b[0m \u001b[0;34m=\u001b[0m \u001b[0mfn\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0mparam\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0m_grad\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0mdata\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n",
      "\u001b[0;32m~/py3.6.3/lib/python3.6/site-packages/torch/nn/modules/module.py\u001b[0m in \u001b[0;36m<lambda>\u001b[0;34m(t)\u001b[0m\n\u001b[1;32m    256\u001b[0m             \u001b[0mModule\u001b[0m\u001b[0;34m:\u001b[0m \u001b[0mself\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[1;32m    257\u001b[0m         \"\"\"\n\u001b[0;32m--> 258\u001b[0;31m         \u001b[0;32mreturn\u001b[0m \u001b[0mself\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0m_apply\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0;32mlambda\u001b[0m \u001b[0mt\u001b[0m\u001b[0;34m:\u001b[0m \u001b[0mt\u001b[0m\u001b[0;34m.\u001b[0m\u001b[0mcuda\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0mdevice\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n\u001b[0m\u001b[1;32m    259\u001b[0m \u001b[0;34m\u001b[0m\u001b[0m\n\u001b[1;32m    260\u001b[0m     \u001b[0;32mdef\u001b[0m \u001b[0mcpu\u001b[0m\u001b[0;34m(\u001b[0m\u001b[0mself\u001b[0m\u001b[0;34m)\u001b[0m\u001b[0;34m:\u001b[0m\u001b[0;34m\u001b[0m\u001b[0m\n",
      "\u001b[0;31mRuntimeError\u001b[0m: cuda runtime error (59) : device-side assert triggered at /pytorch/aten/src/THC/generic/THCTensorCopy.cpp:20"
     ]
    }
   ],
   "source": [
    "#build model\n",
    "rnn1_type = params['rnn1_type'] \n",
    "rnn_1 = rnn_types[rnn1_type]\n",
    "rnn2_type = params['rnn2_type']\n",
    "rnn_2 = rnn_types[rnn2_type]\n",
    "bi = params['bi']\n",
    "hidden_dim1 = params['hidden_dim1']\n",
    "hidden_dim2 = params['hidden_dim2']\n",
    "num_classes = params['num_classes']\n",
    "batch_size = params['batch_size']\n",
    "cuda_on = params['cuda_on']\n",
    "\n",
    "weights_matrix = torch.from_numpy(emb_weight)\n",
    "model = two_stage_RNN(rnn_1, hidden_dim1, bi, rnn_2, hidden_dim2, batch_size, cuda_on, num_classes)\n",
    "model_parameters = filter(lambda p: p.requires_grad, model.parameters())\n",
    "print('The number of train parameters', sum([np.prod(p.size()) for p in model_parameters]))\n",
    "model = model.cuda()\n",
    "\n",
    "#parameter for training\n",
    "learning_rate = params['learning_rate']\n",
    "num_epochs = params['num_epochs'] # number epoch to train\n",
    "\n",
    "# Criterion and Optimizer\n",
    "#pos_weight=torch.Tensor([40,]).cuda()\n",
    "criterion = nn.BCEWithLogitsLoss() #torch.nn.BCELoss(); torch.nn.CrossEntropyLoss()\n",
    "optimizer = torch.optim.Adam(model.parameters(), lr=learning_rate)\n",
    "\n",
    "train_loss_list = []\n",
    "\n",
    "for epoch in range(num_epochs):\n",
    "    for i, (steps_batch, lengths_batch, labels_batch) in enumerate(train_loader):\n",
    "        for step_id in range(6):\n",
    "            lengths_batch[step_id] = lengths_batch[step_id].cuda()\n",
    "            steps_batch[step_id] = steps_batch[step_id].cuda() \n",
    "        model.train()\n",
    "        optimizer.zero_grad()\n",
    "        outputs = model(steps_batch, lengths_batch)\n",
    "        loss = criterion(outputs, labels_batch.view(-1,1).float().cuda()) \n",
    "        train_loss_list.append(loss.item())\n",
    "        loss.backward()\n",
    "        optimizer.step()\n",
    "        # validate every 100 iterations\n",
    "        if i % 10 == 0:\n",
    "            # validate\n",
    "#             print('---------------------')\n",
    "#             for p in model.parameters():\n",
    "#                 if p.requires_grad:\n",
    "#                     print(p.name, p.size(), p.requires_grad, torch.mean(torch.abs(p.data)), torch.mean(torch.abs(p.grad)))\n",
    "#                     break\n",
    "            val_auc, val_acc = test_model(val_loader, model)\n",
    "            print('{}/{}, Step:{}/{}, TrainLoss:{:.6f}, ValAUC:{:.6f} ValAcc:{:.6f}'.format(\n",
    "                epoch+1, num_epochs, i+1, len(train_loader), loss, val_auc, val_acc))\n",
    "    val_auc, val_acc = test_model(val_loader, model)\n",
    "    train_auc, train_acc = test_model(train_loader, model)\n",
    "    print('Epoch: [{}/{}], trainAUC: {:.6f}, trainAcc: {:.6f}'.format(epoch+1, num_epochs, train_auc, train_acc))\n",
    "    print('Epoch: [{}/{}], ValAUC: {:.6f}, ValAcc: {:.6f}'.format(epoch+1, num_epochs, val_auc, val_acc))"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 138,
   "metadata": {},
   "outputs": [],
   "source": [
    "def model_train(rnn_1,hidden_dim1,bi,rnn_2, hidden_dim2, batch_size, cuda_on, num_classes):\n",
    "    model = two_stage_RNN(rnn_1, hidden_dim1, bi, rnn_2, hidden_dim2, batch_size, cuda_on, num_classes)\n",
    "    model_parameters = filter(lambda p: p.requires_grad, model.parameters())\n",
    "    print('The number of train parameters', sum([np.prod(p.size()) for p in model_parameters]))\n",
    "    model = model.cuda()\n",
    "\n",
    "    #parameter for training\n",
    "    learning_rate = params['learning_rate']\n",
    "    num_epochs = params['num_epochs'] # number epoch to train\n",
    "\n",
    "    # Criterion and Optimizer\n",
    "    criterion = nn.BCEWithLogitsLoss() #torch.nn.BCELoss(); torch.nn.CrossEntropyLoss()\n",
    "    optimizer = torch.optim.Adam(model.parameters(), lr=learning_rate)\n",
    "    \n",
    "    \n",
    "    train_loss_list = []\n",
    "    train_AUC_list = []\n",
    "    val_AUC_list = []\n",
    "    train_ACC_list = []\n",
    "    val_ACC_list = []\n",
    "    for epoch in range(num_epochs):\n",
    "        for i, (steps_batch, lengths_batch, labels_batch) in enumerate(train_loader):\n",
    "            for step_id in range(6):\n",
    "                lengths_batch[step_id] = lengths_batch[step_id].cuda()\n",
    "                steps_batch[step_id] = steps_batch[step_id].cuda() \n",
    "            model.train()\n",
    "            optimizer.zero_grad()\n",
    "            outputs = model(steps_batch, lengths_batch)\n",
    "            loss = criterion(outputs, labels_batch.view(-1,1).float().cuda()) \n",
    "            train_loss_list.append(loss.item())\n",
    "            loss.backward()\n",
    "            optimizer.step()\n",
    "            # validate every 10 iterations\n",
    "            if i % 10 == 0:\n",
    "                val_auc, val_acc = test_model(val_loader, model)\n",
    "                print('{}/{}, Step:{}/{}, TrainLoss:{:.6f}, ValAUC:{:.6f} ValAcc:{:.6f}'.format(\n",
    "                    epoch+1, num_epochs, i+1, len(train_loader), loss, val_auc, val_acc))\n",
    "        val_auc, val_acc = test_model(val_loader, model)\n",
    "        train_auc, train_acc = test_model(train_loader, model)\n",
    "        train_AUC_list.append(train_auc)\n",
    "        val_AUC_list.append(val_auc)\n",
    "        train_ACC_list.append(train_acc)\n",
    "        val_ACC_list.append(val_acc)\n",
    "        print('Epoch: [{}/{}], trainAUC: {:.6f}, trainAcc: {:.6f}'.format(epoch+1, num_epochs, train_auc, train_acc))\n",
    "        print('Epoch: [{}/{}], ValAUC: {:.6f}, ValAcc: {:.6f}'.format(epoch+1, num_epochs, val_auc, val_acc))\n",
    "        return train_loss_list, train_AUC_list, val_AUC_list, train_ACC_list, val_ACC_list  "
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 57,
   "metadata": {},
   "outputs": [
    {
     "data": {
      "image/png": "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\n",
      "text/plain": [
       "<matplotlib.figure.Figure at 0x2ae286129ac8>"
      ]
     },
     "metadata": {},
     "output_type": "display_data"
    }
   ],
   "source": [
    "plt.plot(train_loss_list)\n",
    "plt.show()"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 56,
   "metadata": {},
   "outputs": [],
   "source": [
    "#train_loss_list"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 241,
   "metadata": {},
   "outputs": [
    {
     "name": "stdout",
     "output_type": "stream",
     "text": [
      "two_stage_RNN(\n",
      "  (embedding): Embedding(3193, 50)\n",
      "  (rnn_each_step): ModuleList(\n",
      "    (0): GRU(50, 30, batch_first=True, bidirectional=True)\n",
      "    (1): GRU(50, 30, batch_first=True, bidirectional=True)\n",
      "    (2): GRU(50, 30, batch_first=True, bidirectional=True)\n",
      "    (3): GRU(50, 30, batch_first=True, bidirectional=True)\n",
      "    (4): GRU(50, 30, batch_first=True, bidirectional=True)\n",
      "    (5): GRU(50, 30, batch_first=True, bidirectional=True)\n",
      "  )\n",
      "  (steps_rnn): GRU(60, 30)\n",
      "  (linear): Linear(in_features=30, out_features=1, bias=True)\n",
      ")\n"
     ]
    }
   ],
   "source": [
    "print(model)"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 33,
   "metadata": {},
   "outputs": [
    {
     "name": "stdout",
     "output_type": "stream",
     "text": [
      "embedding.weight torch.Size([3193, 50])\n",
      "rnn_each_step.0.weight_ih_l0 torch.Size([90, 50])\n",
      "rnn_each_step.0.weight_hh_l0 torch.Size([90, 30])\n",
      "rnn_each_step.0.bias_ih_l0 torch.Size([90])\n",
      "rnn_each_step.0.bias_hh_l0 torch.Size([90])\n",
      "rnn_each_step.1.weight_ih_l0 torch.Size([90, 50])\n",
      "rnn_each_step.1.weight_hh_l0 torch.Size([90, 30])\n",
      "rnn_each_step.1.bias_ih_l0 torch.Size([90])\n",
      "rnn_each_step.1.bias_hh_l0 torch.Size([90])\n",
      "rnn_each_step.2.weight_ih_l0 torch.Size([90, 50])\n",
      "rnn_each_step.2.weight_hh_l0 torch.Size([90, 30])\n",
      "rnn_each_step.2.bias_ih_l0 torch.Size([90])\n",
      "rnn_each_step.2.bias_hh_l0 torch.Size([90])\n",
      "rnn_each_step.3.weight_ih_l0 torch.Size([90, 50])\n",
      "rnn_each_step.3.weight_hh_l0 torch.Size([90, 30])\n",
      "rnn_each_step.3.bias_ih_l0 torch.Size([90])\n",
      "rnn_each_step.3.bias_hh_l0 torch.Size([90])\n",
      "rnn_each_step.4.weight_ih_l0 torch.Size([90, 50])\n",
      "rnn_each_step.4.weight_hh_l0 torch.Size([90, 30])\n",
      "rnn_each_step.4.bias_ih_l0 torch.Size([90])\n",
      "rnn_each_step.4.bias_hh_l0 torch.Size([90])\n",
      "rnn_each_step.5.weight_ih_l0 torch.Size([90, 50])\n",
      "rnn_each_step.5.weight_hh_l0 torch.Size([90, 30])\n",
      "rnn_each_step.5.bias_ih_l0 torch.Size([90])\n",
      "rnn_each_step.5.bias_hh_l0 torch.Size([90])\n",
      "steps_rnn.weight_ih_l0 torch.Size([90, 30])\n",
      "steps_rnn.weight_hh_l0 torch.Size([90, 30])\n",
      "steps_rnn.bias_ih_l0 torch.Size([90])\n",
      "steps_rnn.bias_hh_l0 torch.Size([90])\n",
      "linear.weight torch.Size([1, 30])\n",
      "linear.bias torch.Size([1])\n"
     ]
    }
   ],
   "source": [
    "for key, val in model.state_dict().items():\n",
    "    print(key, val.size())"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 242,
   "metadata": {},
   "outputs": [],
   "source": [
    "logits_all = []\n",
    "labels_all = []\n",
    "model.eval()\n",
    "for steps_batch, lengths_batch, labels_batch in test_loader:\n",
    "    for step_id in range(6):\n",
    "        lengths_batch[step_id] = lengths_batch[step_id].cuda()\n",
    "        steps_batch[step_id] = steps_batch[step_id].cuda() \n",
    "    logits = model(steps_batch, lengths_batch)\n",
    "    logits_all.extend(list(logits.cpu().detach().numpy()))\n",
    "    labels_all.extend(list(labels_batch.numpy()))\n",
    "logits_all = np.array(logits_all)\n",
    "labels_all = np.array(labels_all)\n",
    "auc = roc_auc_score(labels_all, logits_all)\n",
    "predicts = (logits_all > 0.5).astype(int)\n",
    "acc = np.mean(predicts==labels_all)"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 243,
   "metadata": {},
   "outputs": [
    {
     "data": {
      "text/plain": [
       "0.82168113146898103"
      ]
     },
     "execution_count": 243,
     "metadata": {},
     "output_type": "execute_result"
    }
   ],
   "source": [
    "auc"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 244,
   "metadata": {},
   "outputs": [
    {
     "data": {
      "text/plain": [
       "[<matplotlib.lines.Line2D at 0x2b342ac7c588>]"
      ]
     },
     "execution_count": 244,
     "metadata": {},
     "output_type": "execute_result"
    },
    {
     "data": {
      "image/png": "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\n",
      "text/plain": [
       "<matplotlib.figure.Figure at 0x2b342a7a5160>"
      ]
     },
     "metadata": {},
     "output_type": "display_data"
    }
   ],
   "source": [
    "from sklearn import metrics\n",
    "fpr, tpr, thresholds = metrics.roc_curve(labels_all, logits_all, pos_label=1)\n",
    "plt.plot(fpr, tpr)"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 245,
   "metadata": {},
   "outputs": [
    {
     "name": "stdout",
     "output_type": "stream",
     "text": [
      "torch.Size([90, 50])\n",
      "torch.Size([90, 30])\n",
      "torch.Size([90])\n",
      "torch.Size([90])\n",
      "torch.Size([90, 50])\n",
      "torch.Size([90, 30])\n",
      "torch.Size([90])\n",
      "torch.Size([90])\n",
      "torch.Size([90, 60])\n",
      "torch.Size([90, 30])\n",
      "torch.Size([90])\n",
      "torch.Size([90])\n",
      "torch.Size([1, 30])\n",
      "torch.Size([1])\n"
     ]
    }
   ],
   "source": [
    "for p in model.parameters():\n",
    "    if p.requires_grad:\n",
    "        print(p.size())"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": []
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.6.3"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 2
}

# drug_dae.py
# MLP for LOOCV for every single drug-cell pair

import tensorflow as tf
import pandas as pd
import numpy as np
import sys
import random
import pickle
import math
from subprocess import Popen, PIPE
from sklearn import preprocessing
import cPickle as pickle

# Import functions
sys.path.insert(0, '/tigress/zamalloa/GIT')

from paper_1 import *

# Execute
out_folder    = "/tigress/zamalloa/CGP_FILES/RESULTS/"
exp_arch      = sys.argv[1] # The expression features dae (cgp_encode.py) results
exp_gfilter   = int(sys.argv[2]) # The expression g_filter used (cgp_encode.py)
drug_arch     = sys.argv[3] # The drug features dae (drug_dae.py) results
keepprob      = float(sys.argv[4])
arch          = sys.argv[5] # The architecture to use
drug          = sys.argv[6] # Erlotinib, Paclitaxel
slr           = 0.0001 #0.0000001

# Prep data
exp_data      = exp_encode_parse("c2setcover", exp_gfilter, exp_arch, 0.5)
drug_data     = drug_encode_parse(drug_arch, 0.5)
lobico        = process_paper_lobico("/tigress/zamalloa/PAPERS/LORIO/lobico.csv")

lobico, exp_data, drug_data = drug_exp_lobico_parse(lobico, exp_data, drug_data)
data_feat     = pd.concat([exp_data.loc[lobico.cell_name,].reset_index(drop=True),
                      	   drug_data.loc[lobico.Compound,].reset_index(drop=True)], axis=1)

print("All data:", data_feat.shape)

# We are going to predict per cell on target set
lobico        = lobico.reset_index(drop=True)
target_index  = list(lobico.loc[lobico.Compound==drug].index)
print(len(target_index))

# Prep output files
log_file      = "{}cgpmlp_exp_drug_{}_{}_{}_{}_{}_{}_log".format(out_folder, drug, exp_arch, exp_gfilter, 
														   drug_arch, keepprob, arch)
with open(log_file, "w") as f:
	f.write("Epoch\tbs\tkeep_prob\tcell_name\ttrain_accuracy\tvalid_accuracy\ttest_logit_0\ttest_logit_1\ttest_true\ttest_accuracy")

for cell in target_index:
    
    tf.reset_default_graph()
    cell_name    = lobico.loc[cell].cell_name
    print(cell, cell_name)
    
    test_feat    = np.asarray(data_feat.loc[[cell],:])
    train_index, valid_index = data_split(list(data_feat.drop(cell).index))

    train_feat   = np.asarray(data_feat.loc[train_index])
    valid_feat   = np.asarray(data_feat.loc[valid_index])
    
    train_target = binary_one_hot(
                                 np.asarray(lobico.loc[train_index].value)
                                )
    valid_target = binary_one_hot(
                                 np.asarray(lobico.loc[valid_index].value)
                                 )
    
    test_target  = lobico.loc[cell].value
    test_binary  = binary_one_hot(np.asarray([test_target]))

    pos_weights  = list(lobico.loc[train_index].value)
    ratio        = pos_weights.count(1) / (float(pos_weights.count(0)) + pos_weights.count(1))
    class_weight = tf.constant([[ratio, 1.0-(ratio)]])
#     class_weight = 1000
#     pos_weights  = tf.constant([pos_weights, 1.0])
    
#     print("pos_weights: ", pos_weights)
    print("ratio: ", ratio)
    print("class_weight: ", class_weight)
    
    print("test_target", test_target)
    print("test_binary", test_binary)
    
    # Standardize initial inputs to 0-1 range
    train_feat, valid_feat, test_feat = scale_0_1_multiple(train_feat, valid_feat, test_feat)

    print("SHAPES!!!", train_feat.shape, valid_feat.shape, test_feat.shape)

    # Build graphs
    init_features = train_feat.shape[1]
    print("init arch: ", init_features, arch)
    layers        = arch_layers(init_features, arch)
    print(layers)

    main_dict     = {}

    # Placeholders
    with tf.device('/gpu:0'):
        x           = tf.placeholder(tf.float32, shape=[None, init_features], name="x")
        y_          = tf.placeholder(tf.float32, shape=[None,2], name="y_")
        phase_train = tf.placeholder(tf.bool, name='phase_train')
        keep_prob   = tf.placeholder(tf.float32, name="keep_prob")
        pw          = tf.placeholder(tf.float32, name="pw")

    # Hidden Layers
    with tf.device('/gpu:0'):

        main_dict["h0d"] = tf.nn.dropout(x, 0.9) #Apply noise to features

        for l in xrange(len(layers)-1):
            main_dict["W%s"%(l+1)]  = weight_variable([ layers[l] , layers[l+1]])

            main_dict["h%s"%(l+1)]  = dense_batch_lrelu(tf.matmul(main_dict["h%sd"%l], main_dict["W%s"%(l+1)]), 
                                                        phase_train, scope="h%s%s"%(l+1, cell_name))
            main_dict["h%sd"%(l+1)] = tf.nn.dropout(main_dict["h%s"%(l+1)], keep_prob)

    # Output layer
    W_fcn  = weight_variable([layers[-1], 2])
    b_fcn  = bias_variable([2])
    y_fc   = tf.add(tf.matmul(main_dict["h%sd"%(l+1)], W_fcn),  b_fcn, name="y_fc")

    # Calculate error with original features (denoised)
    with tf.name_scope('cost'):
#         weighted_logits = tf.multiply(y_fc, class_weight) # shape [batch_size, 2]
#         weight_per_label = tf.transpose( tf.matmul(y_, tf.transpose(class_weight)) ) #shape [1, batch_size]
        weight_per_label = tf.reduce_sum(class_weight * y_, axis=1)
        xent = weight_per_label * tf.nn.softmax_cross_entropy_with_logits(logits=y_fc, labels=y_, name="xent_raw") #shape [1, batch_size]
        cost = tf.reduce_mean(xent)
#         cost        = tf.reduce_mean(tf.nn.softmax_cross_entropy_with_logits(labels=y_, logits=weighted_logits)) #CROSS ENTROPY
#         cost        = tf.reduce_mean(tf.nn.weighted_cross_entropy_with_logits(targets=y_, logits=y_fc, pos_weight=class_weight)) #CROSS ENTROPY
        correct_prediction = tf.equal(tf.argmax(y_,1), tf.argmax(y_fc,1)) #BOOLEANS, representing accuracy
        accuracy    = tf.reduce_mean(tf.cast(correct_prediction, tf.float32)) #MEAN OF BOOLEANS, higher better
        probs       = y_fc
        pred_argm   = tf.argmax(y_fc,1)
        true_argm   = tf.argmax(y_,1)

    #################################################### RUNNING ########################################################
    update_ops  = tf.get_collection(tf.GraphKeys.UPDATE_OPS)
    with tf.control_dependencies(update_ops):
        # Ensures that we execute the update_ops before performing the train_step
        train_step            = tf.train.AdamOptimizer(slr).minimize(cost)
    
    sess          = tf.InteractiveSession(config=tf.ConfigProto(log_device_placement=True))
    sess.run(tf.global_variables_initializer())
    
    # Parameters
    batch_size    = 200
    
    # Validation checks
    best_valid     = 0
    patience       = 0 # Epoch-based
    max_patience   = 100 # Epoch-based
    max_training   = 2000 # Maximum number of epochs to train for
    count_batch    = 0 # To get tabs of batch number
    count          = 0 # Number of epochs
    check          = 200 # Batch size during cost checking
    train_checks   = int(math.ceil(train_feat.shape[0] / float(check) )) #n_samples/check
    valid_checks   = int(math.ceil(valid_feat.shape[0] / float(check) ))
    n_batches      = train_feat.shape[0] / batch_size # n_samples/batch_size

    # Train
    print("n_batches: %s"%n_batches)
    print("train_checks: %s"%train_checks)
    while (patience < max_patience) and (count < max_training):
        
        feat_batch   = train_feat[count_batch*batch_size : (count_batch+1)*batch_size, ]
        target_batch = train_target[count_batch*batch_size : (count_batch+1)*batch_size]
        
        train_step.run(feed_dict={x: feat_batch, y_: target_batch,
                                  keep_prob: keepprob, phase_train: True}) #, pw:pos_weights})
        
        if count_batch == (n_batches-1): # Batch limit count, that is a whole epoch has passed
            count_batch = 0
            count+=1 # Epoch number increase
            
            train_accuracy = [accuracy.eval(feed_dict =
                                            {x:train_feat[i*check : (i+1)*check,],
                                             y_:train_target[i*check : (i+1)*check],
                                             keep_prob:1.0, phase_train: False})
                              for i in xrange(train_checks)]
            
            train_accuracy = np.mean(train_accuracy)
            print(train_accuracy)
            
            valid_accuracy = [accuracy.eval(feed_dict =
                                            {x:valid_feat[i*check : (i+1)*check,],
                                             y_:valid_target[i*check : (i+1)*check,],
                                             keep_prob:1.0, phase_train:False})
                              for i in xrange(valid_checks)]
            
            valid_accuracy = np.mean(valid_accuracy)
            print(valid_accuracy)

            test_logit, test_pred, pred_arg, true_arg = sess.run([probs, correct_prediction, pred_argm, true_argm],
                                                                   feed_dict={x:test_feat, y_:test_binary, keep_prob:1.0, phase_train:False})
            
            
            # print("tf_equal of argmax:", test_pred)
            # print("pred logit: ", test_logit, type(test_logit), test_logit.shape, np.argmax(test_logit,axis=1))
            # print("argmax on pred:", pred_arg)
            # print("argmax on true:", true_arg)
            
            with open(log_file, "a") as f:
                f.write("\n%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s"%(count, batch_size, keepprob, cell_name, train_accuracy, valid_accuracy, test_logit[0,0], test_logit[0,1], test_target, test_pred[0]))
            
            # Update validation
            if (valid_accuracy > best_valid) and (count>2):
                best_valid=valid_accuracy
                patience=0
            else:
                patience+=1
        else:
            count_batch+=1
    sess.close()
    print("Done modeling single-cell MLP")

print("DONE")


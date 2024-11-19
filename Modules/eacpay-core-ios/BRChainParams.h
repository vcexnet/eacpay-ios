//
//  BRChainParams.h
//
//  Created by Aaron Voisine on 1/10/18.
//  Copyright (c) 2019 breadwallet LLC
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#ifndef BRChainParams_h
#define BRChainParams_h

#include "BRMerkleBlock.h"
#include "BRSet.h"
#include <assert.h>

typedef struct {
    uint32_t height;
    UInt256 hash;
    uint32_t timestamp;
    uint32_t target;
} BRCheckPoint;

typedef struct {
    const char * const *dnsSeeds; // NULL terminated array of dns seeds
    uint16_t standardPort;
    uint32_t magicNumber;
    uint64_t services;
    int (*verifyDifficulty)(const BRMerkleBlock *block, const BRSet *blockSet); // blockSet must have last 2016 blocks
    const BRCheckPoint *checkpoints;
    size_t checkpointsCount;
} BRChainParams;

static const char *BRMainNetDNSSeeds[] = {
    "dnsseed.deveac.com.", "dnsseed.eacpay.com.", NULL
};

static const char *BRTestNetDNSSeeds[] = {
    "testnet-seed.deveac.com.", "testnet-seed.eacpay.com.", NULL
};

// blockchain checkpoints - these are also used as starting points for partial chain downloads, so they must be at
// difficulty transition boundaries in order to verify the block difficulty at the immediately following transition
static const BRCheckPoint BRMainNetCheckpoints[] = {
    {       0, uint256("21717d4df403301c0538f1cb9af718e483ad06728bbcd8cc6c9511e2f9146ced"), 1386746168, 0x1e0ffff0 },
    {   50000, uint256("6a4f705b7a34de7dc1b6573b3595fde05c7b4303b35ede20a3b945244adc6c70"), 1422050782, 0x1c07ca2d },
    {  101000, uint256("ba5948ef9fce38887df24c54366121437d336bd67a4332508248def0032c5d6e"), 1394402734, 0x1c1ea925 },
    {  200000, uint256("003a4cb3bf206cfc23b9477e1c433280ae1b3393a21aa858aa322e8402204cd0"), 1401043428, 0x1c439a85 },
    {  301000, uint256("c557d7363393148a630a3fda46ca380a202fe82fa594c5e57f88fbece755bb05"), 1409773863, 0x1c0a5921 },
    {  401000, uint256("e43417eb3b583fd28dfbfb38c65763d990b4c370066ac615a08c4c5c3910ebc9"), 1415961678, 0x1c060645 },
    {  500000, uint256("a2989da9f8e785f7040c2e2dfc0177babbf736cfad9f2b401656fea4c3c7c9db"), 1422050782, 0x1c07ca2d },
    {  600000, uint256("85ac8dbbba7a870a45740677be5f35114cb3b70f56d1c93cc2aaf415629037e7"), 1428354796, 0x1c04f0ea },
    {  700000, uint256("450af2f828cdfb29be40d644d39a0858b29fe05b556946db31a7c365cffed705"), 1434998138, 0x1c04b936 },
    {  800001, uint256("a6d915a25e905d1329e482aac91228b168de6e6efb3838df16c21c3ac3a82ea2"), 1441480413, 0x1c071b84 },
    {  900000, uint256("7854a46edbdc4311006a9fd27ae601bb1ebd22fc5e8d6f1757e15237080a545b"), 1449015490, 0x1c01e3c7 },
    { 1000000, uint256("ec070022a4fe9b450e02edd08c6ed355047bc8e65ef05e881b51c212d7c0fe95"), 1455214020, 0x1b5a0352 },
    { 1100000, uint256("4173031420285636eeecfab94e4e62e3a3cf6e144b97b2cc3622c683e09102f0"), 1463143708, 0x1c022049 },
    { 1394462, uint256("ef308b7f477903acd8f300e6f0684c4888ce28c491fc32c1c469bfba6abf091b"), 1492876227, 0x1c0fa788 },
    { 1400000, uint256("4bc57c3a57cc977db9f3bd6a095f51c0c7cc9c30fa8554505fa8f8e33d9f2b80"), 1493281070, 0x1c1db79e },
    { 1573741, uint256("6e4dacfd1684e71a178f29f3e9c714d264e6d385f64c31cdbe532b3204ce4e1d"), 1504259973, 0x1c1b5f1d },
    { 1650000, uint256("70caabb0720c95f67a02eabfde27253eaa8698dc6ea5716631890876b9df421a"), 1510102936, 0x1c0405b0 },
    { 1750000, uint256("8971f1790e58c6de0ea2854872c6ad03752b65567ab8e5c8458ae4a6eb9fb783"), 1516012252, 0x1c023cde },
    { 1888888, uint256("89530dba778db5a540aac6b7b8659cee8909ba445fa5a54ba3023e98e045692d"), 1524071825, 0x1b293964 },
    { 2242222, uint256("98b01e772f0ca3b3ac875857e4f3b6571f8f18b8b896d0cb2feefeca90b69583"), 1544793826, 0x1b339856 },
    { 2460000, uint256("13dcc432b541f34539f0582ebad2ab045db399e58404385ee1e24b4713346a5b"), 1557352598, 0x1b6ca41b },
    { 2856666, uint256("057391a103bca1b54331c53ac81b9e5f588a359ca6a3068a53103c33d0f0e7ef"), 1581957567, 0x1b1e4056 },
    { 3000000, uint256("f5107f3d3f37676b047f3f5e6629369f01c3317ead73f1e0a84f5cdaf0dcb94b"), 1590840773, 0x1c00b044 },
    { 3120000, uint256("c4c45cc1678911470b69d23c82930608b90f3f232a083d9cb84657974ffd91e6"), 1598279059, 0x1c00f5e6 },
    { 3150000, uint256("0c8b9464766314e5c1ccc1a392f257ddc7eb81652eadc8eeb2a909791cdcc4db"), 1600138541, 0x1b751389 },
    { 3200000, uint256("c01897f3b5af04c109c74031d98c6bce2dab606fb8b36e8b28db9a8c4e2027fa"), 1603237795, 0x1c00afcc },
    { 3250000, uint256("abd8e4ee61f54bada412a4e02bc728bbe36cbd0c5516fbc015589e86207beced"), 1606336761, 0x1c01842c },
    { 3300000, uint256("d63e6e1680d276f71926ec6db989b4388fbac18932ebbf73d5d75660f02733aa"), 1609438023, 0x1c035297 },
    { 3345000, uint256("177b2488f6672af4142746a56fd1284bbece74cb59057ddfe90d8a6c19e292cf"), 1612092307, 0x1c026e2b },
    { 3400000, uint256("571b854de74f4e23a014c3ef067f71c00036f00b06b9b2acee606f20b6f25330"), 1615385933, 0x1c009487 }
};

static const BRCheckPoint BRTestNetCheckpoints[] = {
    {       0, uint256("14b1da80b3d734d36a4a2be97ed2c9d49e79c47213d5bcc15b475a1115d28918"), 1386746169, 0x1e0ffff0 }
};

static int BRMainNetVerifyDifficulty(const BRMerkleBlock *block, const BRSet *blockSet)
{
    // const BRMerkleBlock *previous, *b = NULL;
    // uint32_t i;

    // assert(block != NULL);
    // assert(blockSet != NULL);

    // // check if we hit a difficulty transition, and find previous transition block
    // if ((block->height % BLOCK_DIFFICULTY_INTERVAL) == 0) {
    //     for (i = 0, b = block; b && i < BLOCK_DIFFICULTY_INTERVAL; i++) {
    //         b = BRSetGet(blockSet, &b->prevBlock);
    //     }
    // }

    // previous = BRSetGet(blockSet, &block->prevBlock);
    // return BRMerkleBlockVerifyDifficulty(block, previous, (b) ? b->timestamp : 0);
    return 1;
}

static int BRTestNetVerifyDifficulty(const BRMerkleBlock *block, const BRSet *blockSet)
{
    return 1; // XXX skip testnet difficulty check for now
}

static const BRChainParams BRMainNetParams = {
    BRMainNetDNSSeeds,
    35677,      // standardPort
    0xfdf1dbc0, // magicNumber
    0,          // services
    BRMainNetVerifyDifficulty,
    BRMainNetCheckpoints,
    sizeof(BRMainNetCheckpoints) / sizeof(*BRMainNetCheckpoints)};

static const BRChainParams BRTestNetParams = {
    BRTestNetDNSSeeds,
    25677,      // standardPort
    0xf1b6c2fd, // magicNumber
    0,          // services
    BRTestNetVerifyDifficulty,
    BRTestNetCheckpoints,
    sizeof(BRTestNetCheckpoints) / sizeof(*BRTestNetCheckpoints)};

#endif // BRChainParams_h

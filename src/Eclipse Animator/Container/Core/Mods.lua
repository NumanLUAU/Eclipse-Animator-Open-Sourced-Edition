--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)
local Mods = {}
Mods.KINDS = {
	"Loop",
	"Generator",
	"Built-In Function",
	"Envelope",
	"Cycles",
	"Noise",
	"Limits",
	"Stepped Interpolation",
}
local NAMES = {
	Generator = "Generator",
	["Built-In Function"] = "Built-In Function",
	Envelope = "Envelope",
	Cycles = "Cycles",
	Noise = "Noise",
	Limits = "Limits",
	["Stepped Interpolation"] = "Stepped",
}
Mods.FUNCTIONS =
	{ "Sine", "Cosine", "Tangent", "Square Root", "Natural Logarithm", "Normalized Sine" }
Mods.CYCLE_MODES = { "No Cycles", "Repeat Motion", "Repeat with Offset", "Repeat Mirrored" }
Mods.BLENDS = { "Replace", "Add", "Subtract", "Multiply" }
Mods.GENERATOR_MODES = { "Expanded Polynomial", "Factorized Polynomial" }
local U32 = 4294967296
local HASH = {
	162,
	160,
	25,
	59,
	248,
	235,
	170,
	238,
	243,
	28,
	103,
	40,
	29,
	237,
	0,
	222,
	149,
	46,
	220,
	63,
	58,
	130,
	53,
	77,
	108,
	186,
	54,
	208,
	246,
	12,
	121,
	50,
	209,
	89,
	244,
	8,
	139,
	99,
	137,
	47,
	184,
	180,
	151,
	131,
	242,
	143,
	24,
	199,
	81,
	20,
	101,
	135,
	72,
	32,
	66,
	168,
	128,
	181,
	64,
	19,
	178,
	34,
	126,
	87,
	188,
	127,
	107,
	157,
	134,
	76,
	200,
	219,
	124,
	213,
	37,
	78,
	90,
	85,
	116,
	80,
	205,
	179,
	122,
	187,
	195,
	203,
	182,
	226,
	228,
	236,
	253,
	152,
	11,
	150,
	211,
	158,
	92,
	161,
	100,
	241,
	129,
	97,
	225,
	196,
	36,
	114,
	73,
	140,
	144,
	75,
	132,
	52,
	56,
	171,
	120,
	202,
	31,
	1,
	215,
	147,
	17,
	193,
	88,
	169,
	49,
	249,
	68,
	109,
	191,
	51,
	156,
	95,
	9,
	148,
	163,
	133,
	6,
	198,
	154,
	30,
	123,
	70,
	21,
	48,
	39,
	43,
	27,
	113,
	60,
	91,
	214,
	111,
	98,
	172,
	79,
	194,
	192,
	14,
	177,
	35,
	167,
	223,
	71,
	176,
	119,
	105,
	5,
	233,
	230,
	231,
	118,
	115,
	15,
	254,
	110,
	155,
	86,
	239,
	18,
	165,
	55,
	252,
	174,
	217,
	3,
	142,
	221,
	16,
	185,
	206,
	201,
	141,
	218,
	42,
	189,
	104,
	23,
	159,
	190,
	212,
	10,
	204,
	210,
	232,
	67,
	61,
	112,
	183,
	2,
	125,
	153,
	216,
	13,
	96,
	138,
	4,
	44,
	62,
	146,
	229,
	175,
	83,
	7,
	224,
	41,
	166,
	197,
	227,
	245,
	247,
	74,
	65,
	38,
	106,
	22,
	94,
	82,
	45,
	33,
	173,
	240,
	145,
	255,
	234,
	84,
	250,
	102,
	26,
	69,
	57,
	207,
	117,
	164,
	136,
	251,
	93,
	162,
	160,
	25,
	59,
	248,
	235,
	170,
	238,
	243,
	28,
	103,
	40,
	29,
	237,
	0,
	222,
	149,
	46,
	220,
	63,
	58,
	130,
	53,
	77,
	108,
	186,
	54,
	208,
	246,
	12,
	121,
	50,
	209,
	89,
	244,
	8,
	139,
	99,
	137,
	47,
	184,
	180,
	151,
	131,
	242,
	143,
	24,
	199,
	81,
	20,
	101,
	135,
	72,
	32,
	66,
	168,
	128,
	181,
	64,
	19,
	178,
	34,
	126,
	87,
	188,
	127,
	107,
	157,
	134,
	76,
	200,
	219,
	124,
	213,
	37,
	78,
	90,
	85,
	116,
	80,
	205,
	179,
	122,
	187,
	195,
	203,
	182,
	226,
	228,
	236,
	253,
	152,
	11,
	150,
	211,
	158,
	92,
	161,
	100,
	241,
	129,
	97,
	225,
	196,
	36,
	114,
	73,
	140,
	144,
	75,
	132,
	52,
	56,
	171,
	120,
	202,
	31,
	1,
	215,
	147,
	17,
	193,
	88,
	169,
	49,
	249,
	68,
	109,
	191,
	51,
	156,
	95,
	9,
	148,
	163,
	133,
	6,
	198,
	154,
	30,
	123,
	70,
	21,
	48,
	39,
	43,
	27,
	113,
	60,
	91,
	214,
	111,
	98,
	172,
	79,
	194,
	192,
	14,
	177,
	35,
	167,
	223,
	71,
	176,
	119,
	105,
	5,
	233,
	230,
	231,
	118,
	115,
	15,
	254,
	110,
	155,
	86,
	239,
	18,
	165,
	55,
	252,
	174,
	217,
	3,
	142,
	221,
	16,
	185,
	206,
	201,
	141,
	218,
	42,
	189,
	104,
	23,
	159,
	190,
	212,
	10,
	204,
	210,
	232,
	67,
	61,
	112,
	183,
	2,
	125,
	153,
	216,
	13,
	96,
	138,
	4,
	44,
	62,
	146,
	229,
	175,
	83,
	7,
	224,
	41,
	166,
	197,
	227,
	245,
	247,
	74,
	65,
	38,
	106,
	22,
	94,
	82,
	45,
	33,
	173,
	240,
	145,
	255,
	234,
	84,
	250,
	102,
	26,
	69,
	57,
	207,
	117,
	164,
	136,
	251,
	93,
}
local VECTORS = {
	0.33783,
	0.715698,
	-0.611206,
	-0.944031,
	-0.326599,
	-0.045624,
	-0.101074,
	-0.416443,
	-0.903503,
	0.799286,
	0.49411,
	-0.341949,
	-0.854645,
	0.518036,
	0.033936,
	0.42514,
	-0.437866,
	-0.792114,
	-0.358948,
	0.597046,
	0.717377,
	-0.985413,
	0.144714,
	0.089294,
	-0.601776,
	-0.33728,
	-0.723907,
	-0.449921,
	0.594513,
	0.666382,
	0.208313,
	-0.10791,
	0.972076,
	0.575317,
	0.060425,
	0.815643,
	0.293365,
	-0.875702,
	-0.383453,
	0.293762,
	0.465759,
	0.834686,
	-0.846008,
	-0.233398,
	-0.47934,
	-0.115814,
	0.143036,
	-0.98291,
	0.204681,
	-0.949036,
	-0.239532,
	0.946716,
	-0.263947,
	0.184326,
	-0.235596,
	0.573822,
	0.784332,
	0.203705,
	-0.372253,
	-0.905487,
	0.756989,
	-0.651031,
	0.055298,
	0.497803,
	0.814697,
	-0.297363,
	-0.16214,
	0.063995,
	-0.98468,
	-0.329254,
	0.834381,
	0.441925,
	0.703827,
	-0.527039,
	-0.476227,
	0.956421,
	0.266113,
	0.119781,
	0.480133,
	0.482849,
	0.7323,
	-0.18631,
	0.961212,
	-0.203125,
	-0.748474,
	-0.656921,
	-0.090393,
	-0.085052,
	-0.165253,
	0.982544,
	-0.76947,
	0.628174,
	-0.115234,
	0.383148,
	0.537659,
	0.751068,
	0.616486,
	-0.668488,
	-0.415924,
	-0.259979,
	-0.630005,
	0.73175,
	0.570953,
	-0.087952,
	0.816223,
	-0.458008,
	0.023254,
	0.888611,
	-0.196167,
	0.976563,
	-0.088287,
	-0.263885,
	-0.69812,
	-0.665527,
	0.437134,
	-0.892273,
	-0.112793,
	-0.621674,
	-0.230438,
	0.748566,
	0.232422,
	0.900574,
	-0.367249,
	0.22229,
	-0.796143,
	0.562744,
	-0.665497,
	-0.73764,
	0.11377,
	0.670135,
	0.704803,
	0.232605,
	0.895599,
	0.429749,
	-0.114655,
	-0.11557,
	-0.474243,
	0.872742,
	0.621826,
	0.604004,
	-0.498444,
	-0.832214,
	0.012756,
	0.55426,
	-0.702484,
	0.705994,
	-0.089661,
	-0.692017,
	0.649292,
	0.315399,
	-0.175995,
	-0.977997,
	0.111877,
	0.096954,
	-0.04953,
	0.994019,
	0.635284,
	-0.606689,
	-0.477783,
	-0.261261,
	-0.607422,
	-0.750153,
	0.983276,
	0.165436,
	0.075958,
	-0.29837,
	0.404083,
	-0.864655,
	-0.638672,
	0.507721,
	0.578156,
	0.388214,
	0.412079,
	0.824249,
	0.556183,
	-0.208832,
	0.804352,
	0.778442,
	0.562012,
	0.27951,
	-0.616577,
	0.781921,
	-0.091522,
	0.196289,
	0.051056,
	0.979187,
	-0.121216,
	0.207153,
	-0.970734,
	-0.173401,
	-0.384735,
	0.906555,
	0.161499,
	-0.723236,
	-0.671387,
	0.178497,
	-0.006226,
	-0.983887,
	-0.126038,
	0.15799,
	0.97934,
	0.830475,
	-0.024811,
	0.556458,
	-0.510132,
	-0.76944,
	0.384247,
	0.81424,
	0.200104,
	-0.544891,
	-0.112549,
	-0.393311,
	-0.912445,
	0.56189,
	0.152222,
	-0.813049,
	0.198914,
	-0.254517,
	-0.946381,
	-0.41217,
	0.690979,
	-0.593811,
	-0.407257,
	0.324524,
	0.853668,
	-0.690186,
	0.366119,
	-0.624115,
	-0.428345,
	0.844147,
	-0.322296,
	-0.21228,
	-0.297546,
	-0.930756,
	-0.273071,
	0.516113,
	0.811798,
	0.928314,
	0.371643,
	0.007233,
	0.785828,
	-0.479218,
	-0.390778,
	-0.704895,
	0.058929,
	0.706818,
	0.173248,
	0.203583,
	0.963562,
	0.422211,
	-0.904297,
	-0.062469,
	-0.363312,
	-0.182465,
	0.913605,
	0.254028,
	-0.552307,
	-0.793945,
	-0.28891,
	-0.765747,
	-0.574554,
	0.058319,
	0.291382,
	0.954803,
	0.946136,
	-0.303925,
	0.111267,
	-0.078156,
	0.443695,
	-0.892731,
	0.182098,
	0.89389,
	0.409515,
	-0.680298,
	-0.213318,
	0.701141,
	0.062469,
	0.848389,
	-0.525635,
	-0.72879,
	-0.641846,
	0.238342,
	-0.88089,
	0.427673,
	0.202637,
	-0.532501,
	-0.21405,
	0.818878,
	0.948975,
	-0.305084,
	0.07962,
	0.925446,
	0.374664,
	0.055817,
	0.820923,
	0.565491,
	0.079102,
	0.25882,
	0.099792,
	-0.960724,
	-0.294617,
	0.910522,
	0.289978,
	0.137115,
	0.320038,
	-0.937408,
	-0.908386,
	0.345276,
	-0.235718,
	-0.936218,
	0.138763,
	0.322754,
	0.366577,
	0.925934,
	-0.090637,
	0.309296,
	-0.686829,
	-0.657684,
	0.66983,
	0.024445,
	0.742065,
	-0.917999,
	-0.059113,
	-0.392059,
	0.365509,
	0.462158,
	-0.807922,
	0.083374,
	0.996399,
	-0.014801,
	0.593842,
	0.253143,
	-0.763672,
	0.974976,
	-0.165466,
	0.148285,
	0.918976,
	0.137299,
	0.369537,
	0.294952,
	0.694977,
	0.655731,
	0.943085,
	0.152618,
	-0.295319,
	0.58783,
	-0.598236,
	0.544495,
	0.203796,
	0.678223,
	0.705994,
	-0.478821,
	-0.661011,
	0.577667,
	0.719055,
	-0.1698,
	-0.673828,
	-0.132172,
	-0.965332,
	0.225006,
	-0.981873,
	-0.14502,
	0.121979,
	0.763458,
	0.579742,
	0.284546,
	-0.893188,
	0.079681,
	0.442474,
	-0.795776,
	-0.523804,
	0.303802,
	0.734955,
	0.67804,
	-0.007446,
	0.15506,
	0.986267,
	-0.056183,
	0.258026,
	0.571503,
	-0.778931,
	-0.681549,
	-0.702087,
	-0.206116,
	-0.96286,
	-0.177185,
	0.203613,
	-0.470978,
	-0.515106,
	0.716095,
	-0.740326,
	0.57135,
	0.354095,
	-0.56012,
	-0.824982,
	-0.074982,
	-0.507874,
	0.753204,
	0.417969,
	-0.503113,
	0.038147,
	0.863342,
	0.594025,
	0.673553,
	-0.439758,
	-0.119873,
	-0.005524,
	-0.992737,
	0.098267,
	-0.213776,
	0.971893,
	-0.615631,
	0.643951,
	0.454163,
	0.896851,
	-0.441071,
	0.032166,
	-0.555023,
	0.750763,
	-0.358093,
	0.398773,
	0.304688,
	0.864929,
	-0.722961,
	0.303589,
	0.620544,
	-0.63559,
	-0.621948,
	-0.457306,
	-0.293243,
	0.072327,
	0.953278,
	-0.491638,
	0.661041,
	-0.566772,
	-0.304199,
	-0.572083,
	-0.761688,
	0.908081,
	-0.398956,
	0.127014,
	-0.523621,
	-0.549683,
	-0.650848,
	-0.932922,
	-0.19986,
	0.299408,
	0.099426,
	0.140869,
	0.984985,
	-0.020325,
	-0.999756,
	-0.002319,
	0.952667,
	0.280853,
	-0.11615,
	-0.971893,
	0.082581,
	0.220337,
	0.65921,
	0.705292,
	-0.260651,
	0.733063,
	-0.175537,
	0.657043,
	-0.555206,
	0.429504,
	-0.712189,
	0.400421,
	-0.89859,
	0.179352,
	0.750885,
	-0.19696,
	0.630341,
	0.785675,
	-0.569336,
	0.241821,
	-0.058899,
	-0.464111,
	0.883789,
	0.129608,
	-0.94519,
	0.299622,
	-0.357819,
	0.907654,
	0.219238,
	-0.842133,
	-0.439117,
	-0.312927,
	-0.313477,
	0.84433,
	0.434479,
	-0.241211,
	0.053253,
	0.968994,
	0.063873,
	0.823273,
	0.563965,
	0.476288,
	0.862152,
	-0.172516,
	0.620941,
	-0.298126,
	0.724915,
	0.25238,
	-0.749359,
	-0.612122,
	-0.577545,
	0.386566,
	0.718994,
	-0.406342,
	-0.737976,
	0.538696,
	0.04718,
	0.556305,
	0.82959,
	-0.802856,
	0.587463,
	0.101166,
	-0.707733,
	-0.705963,
	0.026428,
	0.374908,
	0.68457,
	0.625092,
	0.472137,
	0.208405,
	-0.856506,
	-0.703064,
	-0.581085,
	-0.409821,
	-0.417206,
	-0.736328,
	0.532623,
	-0.447876,
	-0.20285,
	-0.870728,
	0.086945,
	-0.990417,
	0.107086,
	0.183685,
	0.018341,
	-0.982788,
	0.560638,
	-0.428864,
	0.708282,
	0.296722,
	-0.952576,
	-0.0672,
	0.135773,
	0.990265,
	0.030243,
	-0.068787,
	0.654724,
	0.752686,
	0.762604,
	-0.551758,
	0.337585,
	-0.819611,
	-0.407684,
	0.402466,
	-0.727844,
	-0.55072,
	-0.408539,
	-0.855774,
	-0.480011,
	0.19281,
	0.693176,
	-0.079285,
	0.716339,
	0.226013,
	0.650116,
	-0.725433,
	0.246704,
	0.953369,
	-0.173553,
	-0.970398,
	-0.239227,
	-0.03244,
	0.136383,
	-0.394318,
	0.908752,
	0.813232,
	0.558167,
	0.164368,
	0.40451,
	0.549042,
	-0.731323,
	-0.380249,
	-0.566711,
	0.730865,
	0.022156,
	0.932739,
	0.359741,
	0.00824,
	0.996552,
	-0.082306,
	0.956635,
	-0.065338,
	-0.283722,
	-0.743561,
	0.008209,
	0.668579,
	-0.859589,
	-0.509674,
	0.035767,
	-0.852234,
	0.363678,
	-0.375977,
	-0.201965,
	-0.970795,
	-0.12915,
	0.313477,
	0.947327,
	0.06546,
	-0.254028,
	-0.528259,
	0.81015,
	0.628052,
	0.601105,
	0.49411,
	-0.494385,
	0.868378,
	0.037933,
	0.275635,
	-0.086426,
	0.957336,
	-0.197937,
	0.468903,
	-0.860748,
	0.895599,
	0.399384,
	0.195801,
	0.560791,
	0.825012,
	-0.069214,
	0.304199,
	-0.849487,
	0.43103,
	0.096375,
	0.93576,
	0.339111,
	-0.051422,
	0.408966,
	-0.911072,
	0.330444,
	0.942841,
	-0.042389,
	-0.452362,
	-0.786407,
	0.420563,
	0.134308,
	-0.933472,
	-0.332489,
	0.80191,
	-0.566711,
	-0.188934,
	-0.987946,
	-0.105988,
	0.112518,
	-0.24408,
	0.892242,
	-0.379791,
	-0.920502,
	0.229095,
	-0.316376,
	0.7789,
	0.325958,
	0.535706,
	-0.912872,
	0.185211,
	-0.36377,
	-0.184784,
	0.565369,
	-0.803833,
	-0.018463,
	0.119537,
	0.992615,
	-0.259247,
	-0.935608,
	0.239532,
	-0.82373,
	-0.449127,
	-0.345947,
	-0.433105,
	0.659515,
	0.614349,
	-0.822754,
	0.378845,
	-0.423676,
	0.687195,
	-0.674835,
	-0.26889,
	-0.246582,
	-0.800842,
	0.545715,
	-0.729187,
	-0.207794,
	0.651978,
	0.653534,
	-0.610443,
	-0.447388,
	0.492584,
	-0.023346,
	0.869934,
	0.609039,
	0.009094,
	-0.79306,
	0.962494,
	-0.271088,
	-0.00885,
	0.2659,
	-0.004913,
	0.963959,
	0.651245,
	0.553619,
	-0.518951,
	0.280548,
	-0.84314,
	0.458618,
	-0.175293,
	-0.983215,
	0.049805,
	0.035339,
	-0.979919,
	0.196045,
	-0.982941,
	0.164307,
	-0.082245,
	0.233734,
	-0.97226,
	-0.005005,
	-0.747253,
	-0.611328,
	0.260437,
	0.645599,
	0.592773,
	0.481384,
	0.117706,
	-0.949524,
	-0.29068,
	-0.535004,
	-0.791901,
	-0.294312,
	-0.627167,
	-0.214447,
	0.748718,
	-0.047974,
	-0.813477,
	-0.57959,
	-0.175537,
	0.477264,
	-0.860992,
	0.738556,
	-0.414246,
	-0.53183,
	0.562561,
	-0.704071,
	0.433289,
	-0.754944,
	0.64801,
	-0.100586,
	0.114716,
	0.044525,
	-0.992371,
	0.966003,
	0.244873,
	-0.082764,
}

local function rotate(x, k)
	return bit32.lrotate(x, k)
end

local function sub(a, b)
	return (a - b) % U32
end

local function final(a, b, c)
	c = bit32.bxor(c, b)
	c = sub(c, rotate(b, 14))
	a = bit32.bxor(a, c)
	a = sub(a, rotate(c, 11))
	b = bit32.bxor(b, a)
	b = sub(b, rotate(a, 25))
	c = bit32.bxor(c, b)
	c = sub(c, rotate(b, 16))
	a = bit32.bxor(a, c)
	a = sub(a, rotate(c, 4))
	b = bit32.bxor(b, a)
	b = sub(b, rotate(a, 14))
	c = bit32.bxor(c, b)
	c = sub(c, rotate(b, 24))
	return c
end

local function hash2(x, y)
	local seed = (0xdeadbeef + (2 * 4) + 13) % U32
	return final((seed + x % U32) % U32, (seed + y % U32) % U32, seed)
end

local function fade(t)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function negateIf(value, condition)
	return condition ~= 0 and -value or value
end

local function grad(h, x, y)
	h = bit32.band(h, 7)
	local u = h < 4 and x or y
	local v = 2 * (h < 4 and y or x)
	return negateIf(u, bit32.band(h, 1)) + negateIf(v, bit32.band(h, 2))
end

local function perlin(x, y)
	local fx0, fy0 = math.floor(x), math.floor(y)
	local fx, fy = x - fx0, y - fy0
	local X, Y = fx0, fy0
	local u, v = fade(fx), fade(fy)
	local v0 = grad(hash2(X, Y), fx, fy)
	local v1 = grad(hash2(X + 1, Y), fx - 1, fy)
	local v2 = grad(hash2(X, Y + 1), fx, fy - 1)
	local v3 = grad(hash2(X + 1, Y + 1), fx - 1, fy - 1)
	local x1 = 1 - u
	return (1 - v) * (v0 * x1 + v1 * u) + v * (v2 * x1 + v3 * u)
end

local function perlinSigned(x, y)
	local cx = math.abs(x) >= 1000000 and 0.5 or 0
	local cy = math.abs(y) >= 1000000 and 0.5 or 0
	return perlin(math.fmod(x, 100000) + cx, math.fmod(y, 100000) + cy) * 0.6616
end

function Mods.fbm(x, y, detail, roughness, lacunarity)
	local fscale, amp, maxamp, sum = 1, 1, 0, 0
	for _ = 0, math.floor(detail) do
		local t = perlinSigned(fscale * x, fscale * y)
		sum += t * amp
		maxamp += amp
		amp *= roughness
		fscale *= lacunarity
	end

	local rmd = detail - math.floor(detail)
	if rmd ~= 0 then
		local t = perlinSigned(fscale * x, fscale * y)
		local sum2 = sum + t * amp
		local a, b = 0.5 * sum / maxamp + 0.5, 0.5 * sum2 / (maxamp + amp) + 0.5
		return (1 - rmd) * a + rmd * b
	end

	return 0.5 * sum / maxamp + 0.5
end

local function legacyNoise(x, y, z)
	local fx, fy, fz = math.floor(x), math.floor(y), math.floor(z)
	local ox, oy, oz = x - fx, y - fy, z - fz
	local ix, iy, iz = fx, fy, fz
	local jx, jy, jz = ox - 1, oy - 1, oz - 1
	local cn1, cn2, cn3, cn4, cn5, cn6 = ox * ox, oy * oy, oz * oz, jx * jx, jy * jy, jz * jz
	cn1 = 1 - 3 * cn1 + 2 * cn1 * ox
	cn2 = 1 - 3 * cn2 + 2 * cn2 * oy
	cn3 = 1 - 3 * cn3 + 2 * cn3 * oz
	cn4 = 1 - 3 * cn4 - 2 * cn4 * jx
	cn5 = 1 - 3 * cn5 - 2 * cn5 * jy
	cn6 = 1 - 3 * cn6 - 2 * cn6 * jz

	local function h(i)
		return HASH[i + 1]
	end

	local b00 = h(h(bit32.band(ix, 255)) + bit32.band(iy, 255))
	local b10 = h(h(bit32.band(ix + 1, 255)) + bit32.band(iy, 255))
	local b01 = h(h(bit32.band(ix, 255)) + bit32.band(iy + 1, 255))
	local b11 = h(h(bit32.band(ix + 1, 255)) + bit32.band(iy + 1, 255))
	local b20, b21 = bit32.band(iz, 255), bit32.band(iz + 1, 255)
	local n = 0.5

	local function add(weight, index, a, b, c)
		local base = 3 * h(index)
		n += weight * (VECTORS[base + 1] * a + VECTORS[base + 2] * b + VECTORS[base + 3] * c)
	end

	add(cn1 * cn2 * cn3, b20 + b00, ox, oy, oz)
	add(cn1 * cn2 * cn6, b21 + b00, ox, oy, jz)
	add(cn1 * cn5 * cn3, b20 + b01, ox, jy, oz)
	add(cn1 * cn5 * cn6, b21 + b01, ox, jy, jz)
	add(cn4 * cn2 * cn3, b20 + b10, jx, oy, oz)
	add(cn4 * cn2 * cn6, b21 + b10, jx, oy, jz)
	add(cn4 * cn5 * cn3, b20 + b11, jx, jy, oz)
	add(cn4 * cn5 * cn6, b21 + b11, jx, jy, jz)
	return math.clamp(n, 0, 1)
end

local function hnoise(size, x, y, z)
	if size == 0 then
		return 0
	end

	return legacyNoise((1 + x) / size, (1 + y) / size, (1 + z) / size)
end

function Mods.turbulence(size, x, y, z, depth)
	local s, d, div = hnoise(size, x, y, z), 0.5, 1
	for _ = 1, depth do
		s += d * hnoise(size * d, x, y, z)
		div += d
		d *= 0.5
	end

	return s / div
end

function Mods.defaultName(kind)
	return NAMES[kind] or kind
end

function Mods.new(kind)
	local smoothLoop = kind == "Loop"
	if smoothLoop then
		kind = "Cycles"
	end

	local m = {
		Type = kind,
		Name = NAMES[kind] or kind,
		Mute = false,
		Expanded = true,
		Active = false,
		UseInfluence = false,
		Influence = 1,
		UseRange = false,
		RangeInSceneTime = false,
		Start = 0,
		End = 0,
		BlendIn = 0,
		BlendOut = 0,
	}
	if kind == "Generator" then
		m.Mode = "Expanded Polynomial"
		m.Order = 1
		m.Coefficients = { 0, 1 }
		m.Additive = false
	elseif kind == "Built-In Function" then
		m.Function = "Sine"
		m.Amplitude = 1
		m.PhaseMultiplier = 1
		m.PhaseOffset = 0
		m.ValueOffset = 0
		m.Additive = false
	elseif kind == "Envelope" then
		m.Reference = 0
		m.Min = -1
		m.Max = 1
		m.Points = {}
	elseif kind == "Cycles" then
		m.BeforeMode = "Repeat Motion"
		m.AfterMode = "Repeat Motion"
		m.BeforeCount = 0
		m.AfterCount = 0
		m.SmoothSeam = smoothLoop
		if smoothLoop then
			m.Name = "Loop"
		end
	elseif kind == "Noise" then
		m.Blend = "Replace"
		m.Scale = 1
		m.Strength = 1
		m.Phase = 1
		m.Offset = 0
		m.Depth = 0
		m.Lacunarity = 2
		m.Roughness = 0.5
		m.Legacy = false
		m.RepeatRange = false
	elseif kind == "Limits" then
		m.UseMinX = false
		m.UseMinY = false
		m.UseMaxX = false
		m.UseMaxY = false
		m.MinX = 0
		m.MinY = 0
		m.MaxX = 0
		m.MaxY = 0
	elseif kind == "Stepped Interpolation" then
		m.Step = 2
		m.StepOffset = 0
		m.UseStepStart = false
		m.UseStepEnd = false
		m.StepStart = 0
		m.StepEnd = 0
	else
		error("Unknown modifier " .. tostring(kind))
	end

	return m
end

function Mods.uniqueName(stack, modifier, wanted)
	local base = wanted ~= "" and wanted or Mods.defaultName(modifier.Type)

	local function taken(name)
		for _, other in stack do
			if other ~= modifier and other.Name == name then
				return true
			end
		end

		return false
	end

	if not taken(base) then
		return base
	end

	local stem = string.match(base, "^(.-)%.%d%d%d+$") or base
	local index = 1
	while taken(string.format("%s.%03d", stem, index)) do
		index += 1
	end

	return string.format("%s.%03d", stem, index)
end

function Mods.clone(value)
	if type(value) ~= "table" then
		return value
	end

	local out = {}
	for k, v in value do
		out[k] = Mods.clone(v)
	end

	return out
end

function Mods.verify(m)
	if m.Type == "Generator" then
		m.Order = math.clamp(math.floor(m.Order or 1), 1, 100)
		local size = m.Mode == "Factorized Polynomial" and m.Order * 2 or m.Order + 1
		m.Coefficients = m.Coefficients or {}
		for i = 1, size do
			m.Coefficients[i] = m.Coefficients[i] or 0
		end

		for i = #m.Coefficients, size + 1, -1 do
			m.Coefficients[i] = nil
		end
	elseif m.Type == "Envelope" then
		table.sort(m.Points, function(a, b)
			return a.Frame < b.Frame
		end)
	end

	return m
end

function Mods.influence(m, t)
	local influence = m.UseInfluence and m.Influence or 1
	if m.UseRange then
		if t < m.Start or t > m.End then
			return 0
		end

		if m.BlendIn ~= 0 and t >= m.Start and t <= m.Start + m.BlendIn then
			return influence * (t - m.Start) / m.BlendIn
		end

		if m.BlendOut ~= 0 and t <= m.End and t >= m.End - m.BlendOut then
			local a, b = m.End, m.End - m.BlendOut
			return influence * (t - a) / (b - a)
		end
	end

	return influence
end

local function inRange(m, t)
	return not m.UseRange or (m.Start <= t and m.End >= t)
end

local function cyclesTime(m, t, range, store)
	store.offset = 0
	if type(range) == "function" then
		range = range()
	end

	if not range then
		return t
	end

	local firstX, firstY, lastX, lastY = range[1], range[2], range[3], range[4]
	local side, mode, cycles, ofs = 0, nil, 0, 0
	if t < firstX then
		if m.BeforeMode ~= "No Cycles" then
			side, mode, cycles, ofs = -1, m.BeforeMode, m.BeforeCount, firstX
		end
	elseif t > lastX then
		if m.AfterMode ~= "No Cycles" then
			side, mode, cycles, ofs = 1, m.AfterMode, m.AfterCount, lastX
		end
	end

	if side == 0 or not mode then
		return t
	end

	local cycdx, cycdy = lastX - firstX, lastY - firstY
	if cycdx == 0 then
		return t
	end

	local cycle = side * (t - ofs) / cycdx
	local cyct = math.fmod(t - ofs, cycdx)
	if cycles ~= 0 and cycle > cycles then
		return t
	end

	local cycyofs = 0
	if mode == "Repeat with Offset" then
		cycyofs = (side < 0 and math.floor((t - ofs) / cycdx) or math.ceil((t - ofs) / cycdx))
			* cycdy
	end

	local out

	local function odd(n)
		return math.fmod(if n < 0 then math.ceil(n) else math.floor(n), 2) ~= 0
	end

	if cyct == 0 then
		out = side == 1 and lastX or firstX
		if mode == "Repeat Mirrored" and odd(cycle) then
			out = side == 1 and firstX or lastX
		end
	elseif mode == "Repeat Mirrored" and odd(cycle + 1) then
		out = side < 0 and firstX - cyct or lastX - cyct
	else
		out = firstX + cyct
	end

	if out < firstX then
		out += cycdx
	end

	if mode == "Repeat with Offset" then
		store.offset = cycyofs
	end

	return out
end

local function steppedTime(m, t)
	if m.UseStepStart and t < m.StepStart then
		return t
	end

	if m.UseStepEnd and t > m.StepEnd then
		return t
	end

	if m.Step == 0 then
		return t
	end

	local q = (t - m.StepOffset) / m.Step
	local block = q < 0 and math.ceil(q) or math.floor(q)
	return block * m.Step + m.StepOffset
end

local function limitsTime(m, t)
	if m.UseMinX and t < m.MinX then
		return m.MinX
	end

	if m.UseMaxX and t > m.MaxX then
		return m.MaxX
	end

	return t
end

local TIME = { Cycles = cyclesTime, ["Stepped Interpolation"] = steppedTime, Limits = limitsTime }

local function generator(m, v, t)
	if m.Mode == "Factorized Polynomial" then
		local value = 1
		local c = m.Coefficients
		for i = 1, m.Order do
			value *= ((c[2 * i - 1] or 0) * t + (c[2 * i] or 0))
		end

		return m.Additive and v + value or value
	end

	local value, power = 0, 1
	for i = 1, m.Order + 1 do
		value += (m.Coefficients[i] or 0) * power
		power *= t
	end

	return m.Additive and v + value or value
end

local function sinc(x)
	if math.abs(x) < 0.0001 then
		return 1
	end

	return math.sin(math.pi * x) / (math.pi * x)
end

local function f32(x)
	return (string.unpack("f", string.pack("f", x)))
end

local function builtin(m, v, t)
	local arg = if m.Function == "Tangent"
		then f32(f32(f32(m.PhaseMultiplier) * f32(t)) + f32(m.PhaseOffset))
		else m.PhaseMultiplier * t + m.PhaseOffset
	local fn
	local kind = m.Function
	if kind == "Sine" then
		fn = math.sin
	elseif kind == "Cosine" then
		fn = math.cos
	elseif kind == "Normalized Sine" then
		fn = sinc
	elseif kind == "Tangent" then
		if math.abs(math.fmod(arg - math.pi / 2, math.pi)) < 1.1920929e-7 then
			if not m.Additive then
				return 0
			end
		else
			fn = math.tan
		end
	elseif kind == "Natural Logarithm" then
		if arg > 1 then
			fn = math.log
		elseif not m.Additive then
			return 0
		end
	elseif kind == "Square Root" then
		if arg > 0 then
			fn = math.sqrt
		elseif not m.Additive then
			return 0
		end
	end

	if not fn then
		return v
	end

	local value = if m.Function == "Tangent"
		then f32(f32(m.Amplitude) * f32(fn(arg)) + f32(m.ValueOffset))
		else m.Amplitude * fn(arg) + m.ValueOffset
	return m.Additive and v + value or value
end

local function envelope(m, v, t)
	local points = m.Points
	if #points == 0 then
		return v
	end

	local low, high
	local first, last = points[1], points[#points]
	if first.Frame >= t then
		low, high = first.Min, first.Max
	elseif last.Frame <= t then
		low, high = last.Min, last.Max
	else
		low, high = 0, 0
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			if a.Frame <= t and b.Frame >= t then
				local diff = b.Frame - a.Frame
				local af, bf = (t - a.Frame) / diff, (b.Frame - t) / diff
				low, high = bf * a.Min + af * b.Min, bf * a.Max + af * b.Max
				break
			end
		end
	end

	local span = m.Max - m.Min
	if span == 0 then
		return v
	end

	local fac = (v - (m.Reference + m.Min)) / span
	return low + fac * (high - low)
end

local function noiseSample(m, t)
	local n
	if m.Legacy then
		n = Mods.turbulence(m.Scale, t - m.Offset, m.Phase, 0.1, m.Depth)
	else
		local scale = m.Scale == 0 and 0 or 1 / m.Scale
		n = Mods.fbm(
			(t - m.Offset) * scale + 0.61803398874,
			m.Phase,
			m.Depth,
			m.Roughness,
			m.Lacunarity
		)
	end

	return n
end

local function noise(m, v, t)
	local n = noiseSample(m, t)
	if m.RepeatRange and m.UseRange and m.End > m.Start then
		local span = m.End - m.Start
		local alpha = math.clamp((t - m.Start) / span, 0, 1)
		local blend = alpha * alpha * (3 - 2 * alpha)
		n = n * (1 - blend) + noiseSample(m, t - span) * blend
	end

	if m.Blend == "Add" then
		return v + n * m.Strength
	elseif m.Blend == "Subtract" then
		return v - n * m.Strength
	elseif m.Blend == "Multiply" then
		return v * n * m.Strength
	end

	return v + (n - 0.5) * m.Strength
end

local function limits(m, v)
	if m.UseMinY and v < m.MinY then
		v = m.MinY
	end

	if m.UseMaxY and v > m.MaxY then
		v = m.MaxY
	end

	return v
end

local VALUE = {
	Generator = generator,
	["Built-In Function"] = builtin,
	Envelope = envelope,
	Noise = noise,
	Limits = limits,
	Cycles = function(_, v, _, store)
		return v + (store.offset or 0)
	end,
}

local function poleOffset(entry, frame)
	if not entry or entry.Off or entry.Muted then
		return 0
	end

	local value = 0
	for _, m in entry.Stack or {} do
		if
			m.RangeInSceneTime
			and m.Type == "Generator"
			and m.Additive
			and not m.Mute
			and inRange(m, frame)
		then
			value += generator(m, 0, frame) * Mods.influence(m, frame)
		end
	end

	return value
end

function Mods.evaluate(entry, frame, baseAt, range)
	if entry and entry.Muted then
		return entry.MuteValue or 0, frame
	end

	local stack = entry and entry.Stack
	if not stack or #stack == 0 or entry.Off then
		return baseAt(frame), frame
	end

	local stores = {}
	local t = frame
	for i = #stack, 1, -1 do
		local m = stack[i]
		local fn = TIME[m.Type]
		if fn and not m.Mute and inRange(m, t) then
			stores[i] = stores[i] or {}
			local n = fn(m, t, range, stores[i])
			local influence = Mods.influence(m, t)
			t = influence * n + (1 - influence) * t
		end
	end

	local v = baseAt(t)
	for i = 1, #stack do
		local m = stack[i]
		local fn = VALUE[m.Type]
		local sampleTime = t
		if
			m.Type == "Noise"
			and m.RepeatRange
			and m.UseRange
			and m.End > m.Start
			and t >= m.Start
		then
			sampleTime = m.Start + (t - m.Start) % (m.End - m.Start)
		end

		local rangeTime = m.RangeInSceneTime and frame or sampleTime
		if
			fn
			and not (m.RangeInSceneTime and m.Type == "Generator" and m.Additive)
			and not m.Mute
			and inRange(m, rangeTime)
		then
			local n = fn(m, v, sampleTime, stores[i] or {})
			local influence = Mods.influence(m, rangeTime)
			v = influence * n + (1 - influence) * v
		end
	end

	return v + poleOffset(entry, frame), t
end

function Mods.keysUsable(entry)
	local stack = entry and entry.Stack
	if not stack or entry.Off then
		return true
	end

	for i = #stack, 1, -1 do
		local m = stack[i]
		if m.Mute then
			continue
		end

		if m.Type == "Cycles" or m.Type == "Stepped Interpolation" or m.Type == "Noise" then
			continue
		end

		if (m.Type == "Generator" or m.Type == "Built-In Function") and m.Additive then
			continue
		end

		return false
	end

	return true
end

function Mods.cycleType(entry)
	local m = entry and not entry.Off and entry.Stack and entry.Stack[1]
	if not m or m.Type ~= "Cycles" or m.Mute or m.UseRange or m.UseInfluence then
		return nil
	end

	if m.BeforeCount ~= 0 or m.AfterCount ~= 0 then
		return nil
	end

	if m.BeforeMode == "Repeat Motion" and m.AfterMode == "Repeat Motion" then
		return "Perfect"
	end

	local function ok(mode)
		return mode == "Repeat Motion" or mode == "Repeat with Offset"
	end

	if ok(m.BeforeMode) and ok(m.AfterMode) then
		return "Offset"
	end

	return nil
end

function Mods.extends(entry)
	if entry and entry.Muted then
		return true
	end

	local stack = entry and not entry.Off and entry.Stack
	if not stack then
		return false
	end

	for _, m in stack do
		if not m.Mute then
			return true
		end
	end

	return false
end

local CHANNELS = {
	loc_x = true,
	loc_y = true,
	loc_z = true,
	rot_x = true,
	rot_y = true,
	rot_z = true,
	qrot_w = true,
	qrot_x = true,
	qrot_y = true,
	qrot_z = true,
	scale_x = true,
	scale_y = true,
	scale_z = true,
}
Mods.CHANNELS = CHANNELS

local function raw()
	return require("RawState").Timeline
end

local function store()
	local state = raw()
	state.CurveModifiers = state.CurveModifiers or {}
	return state.CurveModifiers
end

function Mods.entries(motor)
	local all = raw().CurveModifiers
	return all and all[motor]
end

function Mods.get(motor, id)
	local entries = Mods.entries(motor)
	return entries and entries[id]
end

function Mods.ensure(motor, id)
	assert(CHANNELS[id], "Unknown channel " .. tostring(id))
	local all = store()
	all[motor] = all[motor] or {}
	all[motor][id] = all[motor][id] or { Off = false, Stack = {} }
	return all[motor][id]
end

function Mods.preparePoleRecord(motor, c0, frame)
	local entries = motor and Mods.entries(motor)
	if not entries or typeof(c0) ~= "CFrame" then
		return c0
	end

	return c0
		- Vector3.new(
			poleOffset(entries.loc_x, frame),
			poleOffset(entries.loc_y, frame),
			poleOffset(entries.loc_z, frame)
		)
end

function Mods.prune(motor)
	local entries = Mods.entries(motor)
	if not entries then
		return
	end

	for id, entry in entries do
		if #entry.Stack == 0 and not entry.Off and not entry.Extrapolation and not entry.Muted then
			entries[id] = nil
		end
	end

	if not next(entries) then
		raw().CurveModifiers[motor] = nil
	end
end

function Mods.active(entry)
	for _, m in entry and entry.Stack or {} do
		if m.Active then
			return m
		end
	end

	return nil
end

function Mods.setActive(entry, modifier)
	for _, m in entry.Stack do
		m.Active = m == modifier
	end
end

function Mods.any()
	local all = raw().CurveModifiers
	return all ~= nil and next(all) ~= nil
end

function Mods.hasFor(motors)
	local all = raw().CurveModifiers
	if not all then
		return false
	end

	for _, motor in motors do
		for _, entry in all[motor] or {} do
			if Mods.extends(entry) or entry.Extrapolation then
				return true
			end
		end
	end

	return false
end

function Mods.snapshot(motor)
	return Mods.clone(Mods.entries(motor))
end

function Mods.touch(motor)
	local keys = raw().Keyframes
	local bucket = keys and keys[motor]
	if bucket then
		require("GraphCurves").invalidate(bucket)
	end
end

function Mods.restore(motor, snapshot)
	local all = store()
	all[motor] = Mods.clone(snapshot)
	if all[motor] and not next(all[motor]) then
		all[motor] = nil
	end

	Mods.touch(motor)
end

function Mods.add(entry, kind)
	if kind == "Loop" then
		local first = entry.Stack[1]
		if first and first.Type == "Cycles" then
			local modifier = Mods.new("Loop")
			entry.Stack[1] = modifier
			Mods.setActive(entry, modifier)
			return modifier
		end

		local modifier = Mods.new("Loop")
		table.insert(entry.Stack, 1, modifier)
		Mods.setActive(entry, modifier)
		return modifier
	end

	if kind == "Cycles" and #entry.Stack > 0 then
		return nil,
			"Cannot add 'Cycles' modifier to F-Curve, as 'Cycles' modifier can only be first in stack."
	end

	local m = Mods.new(kind)
	m.Name = Mods.uniqueName(entry.Stack, m, "")
	table.insert(entry.Stack, m)
	Mods.setActive(entry, m)
	return m
end

function Mods.remove(entry, modifier)
	local index = table.find(entry.Stack, modifier)
	if index then
		table.remove(entry.Stack, index)
	end
end

function Mods.move(entry, modifier, index)
	local current = table.find(entry.Stack, modifier)
	if not current then
		return false, "Missing modifier"
	end

	if modifier.Type == "Cycles" then
		return false, "Modifier requires original data"
	end

	local first = entry.Stack[1]
	if first and first.Type == "Cycles" and index == 1 then
		return false, "Modifier requires original data"
	end

	index = math.clamp(index, 1, #entry.Stack)
	if index == current then
		return false
	end

	table.remove(entry.Stack, current)
	table.insert(entry.Stack, index, modifier)
	return true
end

local spans = setmetatable({}, { __mode = "k" })

function Mods.keySpan(bucket, id)
	local Curves = require("GraphCurves")
	local compiled = Curves.compile(bucket)
	local channel = compiled.channels[id]
	if channel and #channel > 0 then
		return channel[1].frame, channel[#channel].frame
	end

	local cached = spans[compiled]
	if not cached then
		local first, last
		for frame, key in compiled.legacy or {} do
			if key.GraphOnly or key.Disabled then
				continue
			end

			if not first or frame < first then
				first = frame
			end

			if not last or frame > last then
				last = frame
			end
		end

		cached = { first = first, last = last }
		spans[compiled] = cached
	end

	return cached.first, cached.last
end

function Mods.bakeBoundaries(motor, bucket, lastFrame, emit)
	for id, entry in Mods.entries(motor) or {} do
		if not entry.Off and not entry.Muted then
			for _, modifier in entry.Stack or {} do
				if modifier.RangeInSceneTime and modifier.UseRange and not modifier.Mute then
					for _, frame in { modifier.Start, modifier.End } do
						if frame >= 0 and frame <= lastFrame then
							emit(frame)
							if frame > 0 then
								emit(math.max(0, frame - 0.0001))
							end

							if frame < lastFrame then
								emit(math.min(lastFrame, frame + 0.0001))
							end
						end
					end
				end
			end
		end

		local m = not entry.Off and entry.Stack and entry.Stack[1]
		if not m or m.Type ~= "Cycles" or m.Mute then
			continue
		end

		local first, last = Mods.keySpan(bucket, id)
		if not first or not last or last <= first then
			continue
		end

		local span = last - first

		local function boundary(frame, before)
			if frame < 0 or frame > lastFrame then
				return
			end

			emit(frame)
			local guard = frame + (before and -0.0001 or 0.0001)
			if guard >= 0 and guard <= lastFrame then
				emit(guard)
			end
		end

		local function seams(origin, direction, count, before)
			local lo =
				math.max(0, math.ceil((direction < 0 and origin - lastFrame or -origin) / span))
			local hi = math.floor((direction < 0 and origin or lastFrame - origin) / span)
			if count ~= 0 then
				hi = math.min(hi, count - 1)
			end

			assert(hi - lo < 1000000, "Cycle period is too short for a sampled export")
			for n = lo, hi do
				boundary(origin + direction * n * span, before)
			end
		end

		if m.BeforeMode == "Repeat Motion" then
			seams(first, -1, m.BeforeCount, true)
		end

		if m.AfterMode == "Repeat Motion" then
			seams(last, 1, m.AfterCount, false)
		end

		if m.BeforeMode ~= "No Cycles" and m.BeforeCount > 0 then
			boundary(first - m.BeforeCount * span, true)
		end

		if m.AfterMode ~= "No Cycles" and m.AfterCount > 0 then
			boundary(last + m.AfterCount * span, false)
		end

		if m.UseRange then
			boundary(m.Start, true)
			boundary(m.Start, false)
			boundary(m.End, true)
			boundary(m.End, false)
		end
	end
end

local function eulerOf(cf, id, bucket, t)
	local Curves = require("GraphCurves")
	local channel = bucket and Curves.compile(bucket).channels[id]
	if channel then
		return Curves.value(channel, t)
	end

	local x, y, z = Curves.euler(cf, Curves.rotationOrder(bucket))
	x, y, z = math.rad(x), math.rad(y), math.rad(z)
	return math.deg(if id == "rot_x" then x elseif id == "rot_y" then y else z)
end

local function quatOf(cf, id, bucket, t)
	local Curves = require("GraphCurves")
	local channel = bucket and Curves.compile(bucket).channels[id]
	if channel then
		return Curves.value(channel, t)
	end

	local q = require("Quaternion").fromCFrame(cf)
	return q[string.sub(id, 6)]
end

function Mods.component(id, cf, bucket, t)
	if id == "loc_x" then
		return cf.X
	elseif id == "loc_y" then
		return cf.Y
	elseif id == "loc_z" then
		return cf.Z
	end

	if string.sub(id, 1, 4) == "rot_" then
		return eulerOf(cf, id, bucket, t)
	end

	return quatOf(cf, id, bucket, t)
end

function Mods.compose(base, values, bucket, t)
	local p = base.Position
	local rotation = base.Rotation
	if values.rot_x or values.rot_y or values.rot_z then
		local x = values.rot_x or eulerOf(base, "rot_x", bucket, t)
		local y = values.rot_y or eulerOf(base, "rot_y", bucket, t)
		local z = values.rot_z or eulerOf(base, "rot_z", bucket, t)
		local Curves = require("GraphCurves")
		rotation = Curves.rotation(x, y, z, Curves.rotationOrder(bucket))
	end

	if values.qrot_w or values.qrot_x or values.qrot_y or values.qrot_z then
		local Quaternion = require("Quaternion")
		local q = Quaternion.fromCFrame(rotation)
		for _, axis in { "w", "x", "y", "z" } do
			local id = "qrot_" .. axis
			if values[id] then
				q[axis] = values[id]
			elseif bucket and require("GraphCurves").compile(bucket).channels[id] then
				q[axis] = quatOf(base, id, bucket, t)
			end
		end

		q = Quaternion.normalize(q)
		rotation = CFrame.new(0, 0, 0, q.x, q.y, q.z, q.w)
	end

	return CFrame.new(values.loc_x or p.X, values.loc_y or p.Y, values.loc_z or p.Z) * rotation
end

function Mods.applyC0(motor, time, fps, localAt, bucket)
	local entries = Mods.entries(motor)
	if not entries then
		return nil
	end

	local cache = {}

	local function at(t)
		local v = cache[t]
		if not v then
			v = localAt(t)
			cache[t] = v
		end

		return v
	end

	local values = {}
	local any = false
	for id, entry in entries do
		if string.sub(id, 1, 6) == "scale_" or not Mods.extends(entry) then
			continue
		end

		if entry.Muted and id:sub(1, 4) == "rot_" then
			any = true
			continue
		end

		local function range()
			local first, last = Mods.keySpan(bucket, id)
			return first
					and {
						first,
						Mods.component(id, at(first / fps), bucket, first / fps),
						last,
						Mods.component(id, at(last / fps), bucket, last / fps),
					}
				or nil
		end

		local function sample(frame)
			local Curves = require("GraphCurves")
			local first = entry.Stack and entry.Stack[1]
			if first and first.SmoothSeam and Mods.cycleType(entry) and bucket then
				local compiled = Curves.compile(bucket)
				local channel = compiled.channels[id]
				if not channel then
					compiled.loopChannels = compiled.loopChannels or {}
					channel = compiled.loopChannels[id]
					if not channel then
						channel = { id = id }
						for _, key in bucket do
							if key.Time and not key.Disabled and not key.GraphOnly then
								table.insert(channel, {
									time = key.Time,
									key = key,
									point = {
										Value = Mods.component(id, at(key.Time), bucket, key.Time),
									},
								})
							end
						end

						table.sort(channel, function(a, b)
							return a.time < b.time
						end)
						compiled.loopChannels[id] = channel
					end
				end

				if #channel >= 3 then
					local view = Curves.loopModifier(channel, entry)
					if view ~= channel then
						return Curves.value(view, frame / fps)
					end
				end
			end

			return Mods.component(id, at(frame / fps), bucket, frame / fps)
		end

		values[id] = Mods.evaluate(entry, time * fps, sample, range)
		any = true
	end

	if not any then
		return nil
	end

	local result = Mods.compose(at(time), values, bucket, time)
	local muted = {}
	local hasMuted = false
	local rotationRest
	for id, entry in entries do
		if entry.Muted then
			if id:sub(1, 4) == "rot_" then
				rotationRest = rotationRest
					or (entry.MuteRest and CFrame.new(table.unpack(entry.MuteRest)))
					or raw().DefaultPose[motor]
					or CFrame.identity
			elseif id:sub(1, 4) == "loc_" then
				muted[id] = entry.MuteValue or 0
				hasMuted = true
			end
		end
	end

	if hasMuted then
		result = Mods.compose(result, muted, nil, time)
	end

	if rotationRest then
		local basis = rotationRest.Rotation
		local Curves = require("GraphCurves")
		local order = Curves.rotationOrder(bucket)
		local x, y, z = Curves.euler(basis:Inverse() * result.Rotation, order)
		if entries.rot_x and entries.rot_x.Muted then
			x = 0
		end

		if entries.rot_y and entries.rot_y.Muted then
			y = 0
		end

		if entries.rot_z and entries.rot_z.Muted then
			z = 0
		end

		result = CFrame.new(result.Position) * basis * Curves.rotation(x, y, z, order)
	end

	return result
end

function Mods.applyScale(motor, time, fps, scaleAt, bucket)
	local entries = Mods.entries(motor)
	if not entries then
		return nil, false
	end

	local cache = {}

	local function at(t)
		local v = cache[t]
		if v == nil then
			v = scaleAt(t) or false
			cache[t] = v
		end

		return v or nil
	end

	local out, any = nil, false
	for id, entry in entries do
		if string.sub(id, 1, 6) ~= "scale_" or not Mods.extends(entry) then
			continue
		end

		local function value(frame)
			local s = at(frame / fps)
			return s and s[id] or 1
		end

		local function range()
			local first, last = Mods.keySpan(bucket, id)
			return first and { first, value(first), last, value(last) } or nil
		end

		out = out or table.clone(at(time) or { scale_x = 1, scale_y = 1, scale_z = 1 })
		out[id] = Mods.evaluate(entry, time * fps, value, range)
		any = true
	end

	return out, any
end

function Mods.collect(rig, state, pathOf)
	local tracks = {}
	for motor, entries in state.CurveModifiers or {} do
		local part = motor.Part1
		local path = part and pathOf(part, rig)
		if not path then
			continue
		end

		local channels = {}
		for id, entry in entries do
			if #entry.Stack > 0 or entry.Off or entry.Extrapolation or entry.Muted then
				channels[id] = Mods.clone(entry)
			end
		end

		if next(channels) then
			table.insert(tracks, { path = path, channels = channels })
		end
	end

	return tracks
end

function Mods.load(tracks, state, resolveMotor)
	state.CurveModifiers = state.CurveModifiers or {}
	for _, track in tracks or {} do
		local motor = resolveMotor(track.path)
		if not motor then
			continue
		end

		local entries = {}
		for id, entry in track.channels or {} do
			if not CHANNELS[id] or type(entry) ~= "table" then
				continue
			end

			local stack = {}
			for _, m in entry.Stack or {} do
				if type(m) == "table" and table.find(Mods.KINDS, m.Type) then
					local fresh = Mods.new(m.Type)
					for k, v in m do
						if fresh[k] ~= nil and type(fresh[k]) == type(v) then
							fresh[k] = v
						end
					end

					table.insert(stack, Mods.verify(fresh))
				end
			end

			entries[id] = {
				Off = entry.Off == true,
				Stack = stack,
				Extrapolation = entry.Extrapolation == "Linear" and "Linear" or nil,
				Muted = entry.Muted == true or nil,
				MuteValue = type(entry.MuteValue) == "number"
						and entry.MuteValue == entry.MuteValue
						and math.abs(entry.MuteValue) < 1e12
						and entry.MuteValue
					or 0,
			}
			if
				entries[id].Muted
				and id:sub(1, 4) == "rot_"
				and type(entry.MuteRest) == "table"
				and #entry.MuteRest == 12
			then
				local valid = true
				for _, v in entry.MuteRest do
					if type(v) ~= "number" or v ~= v or math.abs(v) >= 1e12 then
						valid = false
						break
					end
				end

				if valid then
					entries[id].MuteRest = table.clone(entry.MuteRest)
				end
			end
		end

		if next(entries) then
			state.CurveModifiers[motor] = entries
			Mods.touch(motor)
		end
	end
end

return Mods

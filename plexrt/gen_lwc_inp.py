from pylab import *
import netCDF4 as NC
import sys

def get_z_grid():  # grid info from: https://code.mpimet.mpg.de/projects/icon-lem/wiki/Short_model_description
    dz = [ 382.208, 327.557, 307.888,  294.912,  285.042,  276.981,  270.110,  264.084,  258.691,  253.790,  249.284,  245.104,  241.195,  237.518,  234.042,  230.740,  227.593,  224.582,  221.694,  218.917,  216.241,  213.656,  211.156,  208.733,  206.381,  204.096,  201.873,  199.707,  197.595,  195.534,  193.521,  191.552,  189.626,  187.740,  185.891,  184.079,  182.301,  180.555,  178.841,  177.156,  175.500,  173.870,  172.266,  170.687,  169.132,  167.600,  166.090,  164.600,  163.131,  161.681,  160.250,  158.837,  157.441,  156.062,  154.699,  153.352,  152.019,  150.702,  149.398,  148.107,  146.830,  145.565,  144.312,  143.071,  141.841,  140.622,  139.413,  138.215,  137.026,  135.847,  134.677,  133.516,  132.363,  131.218,  130.081,  128.952,  127.830,  126.715,  125.606,  124.503,  123.407,  122.317,  121.232,  120.152,  119.077,  118.006,  116.941,  115.879,  114.821,  113.767,  112.716,  111.667,  110.622,  109.579,  108.539,  107.500,  106.463,  105.427,  104.392,  103.357,  102.323,  101.289,  100.255,  99.219,  98.183,  97.145,  96.106,  95.064,  94.019,  92.972,  91.920,  90.865,  89.804,  88.739,  87.667,  86.589,  85.504,  84.411,  83.310,  82.198,  81.077,  79.943,  78.798,  77.638,  76.463,  75.272,  74.063,  72.834,  71.583,  70.308,  69.007,  67.676,  66.312,  64.911,  63.469,  61.981,  60.440,  58.839,  57.169,  55.417,  53.570,  51.609,  49.507,  47.231,  44.728,  41.923,  38.683,  34.760,  29.554,  20.000,  0.0 ]
    zm = [ 21000.000   , 20617.792   , 20290.235   , 19982.347   , 19687.435   , 19402.393   , 19125.412   , 18855.302   , 18591.217   , 18332.527   , 18078.737   , 17829.452   , 17584.349   , 17343.154   , 17105.635   , 16871.593   , 16640.853   , 16413.261   , 16188.679   , 15966.985   , 15748.067   , 15531.826   , 15318.170   , 15107.015   , 14898.282   , 14691.901   , 14487.805   , 14285.932   , 14086.225   , 13888.630   , 13693.095   , 13499.575   , 13308.022   , 13118.397   , 12930.657   , 12744.766   , 12560.687   , 12378.386   , 12197.831   , 12018.990   , 11841.834   , 11666.334   , 11492.464   , 11320.198   , 11149.510   , 10980.378   , 10812.778   , 10646.689   , 10482.089   , 10318.958   , 10157.277   , 9997.027    , 9838.190    , 9680.749    , 9524.686    , 9369.987    , 9216.635    , 9064.616    , 8913.914    , 8764.517    , 8616.410    , 8469.580    , 8324.016    , 8179.704    , 8036.633    , 7894.793    , 7754.171    , 7614.758    , 7476.543    , 7339.516    , 7203.669    , 7068.992    , 6935.476    , 6803.113    , 6671.895    , 6541.813    , 6412.861    , 6285.031    , 6158.317    , 6032.711    , 5908.207    , 5784.800    , 5662.484    , 5541.252    , 5421.100    , 5302.024    , 5184.017    , 5067.077    , 4951.198    , 4836.377    , 4722.610    , 4609.895    , 4498.227    , 4387.605    , 4278.026    , 4169.487    , 4061.987    , 3955.525    , 3850.098    , 3745.707    , 3642.350    , 3540.027    , 3438.738    , 3338.483    , 3239.264    , 3141.081    , 3043.935    , 2947.829    , 2852.765    , 2758.746    , 2665.774    , 2573.854    , 2482.990    , 2393.185    , 2304.447    , 2216.779    , 2130.190    , 2044.686    , 1960.274    , 1876.965    , 1794.766    , 1713.690    , 1633.747    , 1554.949    , 1477.311    , 1400.848    , 1325.575    , 1251.512    , 1178.678    , 1107.095    , 1036.786    , 967.780     , 900.104     , 833.792     , 768.881     , 705.412     , 643.431     , 582.990     , 524.151     , 466.982     , 411.564     , 357.994     , 306.385     , 256.878     , 209.648     , 164.919     , 122.997     , 84.314      , 49.554      , 20.000      , 0.000 ]
    return np.array(zm), np.array(dz)


def simple_ex(Ncells=24, Nz=1, default_lwc=1e-3, default_iwc=0, dz=100):
    D=NC.Dataset('lwc_ex_{}_{}.nc'.format(Ncells,Nz),'w')

    D.createDimension('ncells', Ncells)
    D.createDimension('hhl_level', Nz+1)
    D.createDimension('hhl', Nz)

    hhl=D.createVariable('height',float32, dimensions=('hhl',))
    for i in range(Nz):
        hhl[i] = dz/2 + dz*i
    hhl[:] = hhl[::-1]

    hl=D.createVariable('height_level',float32, dimensions=('hhl_level',))
    for i in range(Nz+1):
        hl[i] = 0 + dz*i
    hl[:] = hl[::-1]

    lwc=D.createVariable('clw',float32, dimensions=('hhl','ncells'))

    lwc[:] = 0
    if Ncells==24:
        lwc[Nz/2,[18,19,20,21,23]] = default_lwc

    iwc=D.createVariable('cli',float32, dimensions=('hhl','ncells'))

    iwc[:] = 0
    if Ncells==24:
        iwc[Nz/2,[18,19,20,21,23]] = default_iwc

    D.sync()
    D.close()

def icon_2_lwcfile(fname='/home/f/Fabian.Jakub/work/icon_3d_fine_day_DOM01_ML_20140729T120230Z/3d_fine_day_DOM01_ML_20140729T120230Z.nc'):
    DI = NC.Dataset(fname, 'r')

    Nt, Nz, Ncells = np.shape(DI['clw'])

    D=NC.Dataset('lwc.nc','w')

    D.createDimension('ncells', Ncells)
    D.createDimension('hhl_level', Nz+1)
    D.createDimension('hhl', Nz)

    zm, dz = get_z_grid()
    szm = zm[::-1][:Nz+1][::-1]

    hl=D.createVariable('height_level',float32, dimensions=('hhl_level',))
    hl[:] = szm

    hhl=D.createVariable('height',float32, dimensions=('hhl',))
    hhl[:] = (szm[0:-1]+szm[1:])/2

    def copy_var(varname):
        var=D.createVariable(varname, float32, dimensions=('hhl','ncells'))
        invar = DI[varname][0][::-1][:Nz][::-1]
        var[:] = invar

    copy_var('clw')
    copy_var('cli')

    D.sync()
    D.close()

    DI.close()


import argparse
parser = argparse.ArgumentParser()
parser.add_argument('icon_file', help='icon data file, e.g. /home/f/Fabian.Jakub/work/icon_3d_fine_day_DOM01_ML_20140729T120230Z/3d_fine_day_DOM01_ML_20140729T120230Z.nc')
args = parser.parse_args()

if args.icon_file:
    icon_2_lwcfile(fname=args.icon_file)
#simple_ex()

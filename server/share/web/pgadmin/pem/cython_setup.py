#!/usr/bin/env python

import os
from distutils.core import setup
from distutils.extension import Extension
from Cython.Distutils import build_ext as build_pyx

include_dirs = []
library_dirs = []

if __name__ == '__main__':
    c_macros = [('PRINT_VALIDATION_MSG', '0')]

    try:
        print_debug = os.environ['_PRINT_DEBUG']

        if print_debug == '1':
            c_macros.append(('_PRINT_DEBUG', 1))
        else:
            c_macros.append(('_PRINT_DEBUG', 0))

        openssldir = os.environ['OPENSSL']

        if openssldir and openssldir != '':
            include_dirs.append(openssldir + '/include')
            library_dirs.append(openssldir + '/lib')

    except Exception as e:
        print(e)

    setup(
        name='pem_cython_module',
        ext_modules=[
            Extension('_pem',
                      [
                          'sources/_pem.pyx',
                          '../../../common/pemCrypto.c'
                      ],
                      include_dirs=include_dirs,
                      library_dirs=library_dirs,
                      libraries=['ssl', 'crypto'],
                      define_macros=c_macros
                      )
        ],
        cmdclass={'build_ext': build_pyx}
    )

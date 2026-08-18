///////////////////////////////////////////////////////////////////////////////
//
// Postgres Enterprise Manager
//
// Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
//
///////////////////////////////////////////////////////////////////////////////

/* eslint-env node */
/*eslint no-console: ["error", { allow: ["warn", "error", "info"] }] */
// Import file, libraries and plugins
const path = require('path');
const webpack = require('webpack');
const sourceDir = __dirname + '/pgadmin/static';
// webpack.shim.js contains path references for resolve > alias configuration
// and other util function used in CommonsChunksPlugin.
const webpackShimConfig = require('./webpack.shim');
const PRODUCTION = process.env.NODE_ENV === 'production';
const envType = PRODUCTION ? 'production' : 'development';
const TerserPlugin = require('terser-webpack-plugin');
const MiniCssExtractPlugin = require('mini-css-extract-plugin');
const extractStyle = new MiniCssExtractPlugin({
  filename: '[name].css',
  chunkFilename: '[name].css',
});
webpackShimConfig.resolveAlias = {
  ...Object.fromEntries(
    Object.entries(webpackShimConfig.resolveAlias).filter(
      ([key]) => key !== 'sources'
    )
  ),
  'sources/gettext': path.join(
    __dirname,
    './pgadmin/static/js/pem/reports_gettext'
  ),
  'pgadmin.browser.endpoints': path.join(
    __dirname,
    './pgadmin/browser/templates/browser/js/pem/report_endpoints'
  ),
  sources: webpackShimConfig.resolveAlias['sources'], // Add 'sources' at the end
};
// Expose libraries in app context so they need not to
// require('libname') when used in a module

const providePlugin = new webpack.ProvidePlugin({
  _: 'lodash',
});

const sourceMapDevToolPlugin = new webpack.SourceMapDevToolPlugin({
  columns: true,
});

module.exports = {
  mode: envType,
  devtool: false,
  stats: { children: false },
  // The base directory, an absolute path, for resolving entry points and loaders
  // from configuration.
  context: __dirname,
  // Specify entry points of application
  entry: {
    core_usage_report:
      './pgadmin/pem/tools/core_usage_report/static/js/report.js',
    system_config_report:
      './pgadmin/pem/tools/system_config_report/static/js/report.js',
    capacity_manager_report:
      './pgadmin/pem/management/capacity_manager/static/js/report.js'
  },
  // path: The output directory for generated bundles(defined in entry)
  // Ref: https://webpack.js.org/configuration/output/#output-library
  output: {
    library: 'report',
    libraryTarget: 'var',
    path: __dirname + '/pgadmin/pem/static/js/generated/reports/',
    filename: '[name].js',
    libraryExport: 'default',
    publicPath: '',
  },
  module: {
    // References:
    // Module and Rules: https://webpack.js.org/configuration/module/
    // Loaders: https://webpack.js.org/loaders/
    //
    // imports-loader: it adds dependent modules(use:imports-loader?module1)
    // at the beginning of module it is dependency of like:
    // var jQuery = require('jquery'); var browser = require('pgadmin.browser')
    // It solves number of problems
    // Ref: http:/github.com/webpack-contrib/imports-loader/

    rules: [
      {
        test: /\.jsx?$/,
        exclude: [/node_modules/, /vendor/],
        use: {
          loader: 'babel-loader',
          options: {
            presets: [
              [
                '@babel/preset-env',
                { modules: false, useBuiltIns: 'usage', corejs: 3 },
              ],
              '@babel/preset-react',
              '@babel/preset-typescript',
            ],
            plugins: [
              '@babel/plugin-proposal-class-properties',
              '@babel/proposal-object-rest-spread',
            ],
          },
        },
      },
      {
        test: /external_table.*\.js/,
        use: {
          loader: 'babel-loader',
          options: {
            presets: [
              [
                '@babel/preset-env',
                { modules: false, useBuiltIns: 'usage', corejs: 3 },
              ],
            ],
          },
        },
      },
      {
        test: /\.m?js$/,
        resolve: {
          fullySpecified: false,
        },
      },
      {
        test: /\.tsx?$|\.ts?$/,
        use: {
          loader: 'babel-loader',
          options: {
            presets: [
              [
                '@babel/preset-env',
                { modules: false, useBuiltIns: 'usage', corejs: 3 },
              ],
              '@babel/preset-react',
              '@babel/preset-typescript',
            ],
            plugins: [
              '@babel/plugin-proposal-class-properties',
              '@babel/proposal-object-rest-spread',
            ],
          },
        },
      },
      {
        // Transforms the code in a way that it works in the webpack environment.
        // It uses imports-loader internally to load dependency. Its
        // configuration is specified in webpack.shim.js
        // Ref: https://www.npmjs.com/package/shim-loader
        test: /\.js/,
        exclude: [/external_table/],
        loader: 'shim-loader',
        options: webpackShimConfig,
        include: path.join(__dirname, '/pgadmin/browser'),
      },
      {
        test: /\.(jpe?g|png|gif|svg)$/i,
        type: 'asset',
        parser: {
          dataUrlCondition: {
            maxSize: 4 * 1024, // 4kb
          },
        },
        generator: {
          filename: 'img/[name].[ext]',
        },
        exclude: /vendor/,
      },
      {
        test: /\.(eot|ttf|woff|woff2)$/,
        type: 'asset/inline',
        include: [
          /node_modules/,
          path.join(sourceDir, '/css/'),
          path.join(sourceDir, '/scss/'),
          path.join(sourceDir, '/fonts/'),
        ],
        exclude: /vendor/,
      },
      {
        test: /\.scss$/,
        use: [
          {
            loader: MiniCssExtractPlugin.loader,
            options: {
              publicPath: '',
            },
          },
          { loader: 'css-loader' },
          {
            loader: 'postcss-loader',
            options: {
              postcssOptions: () => ({
                plugins: [require('autoprefixer')()],
              }),
            },
          },
          { loader: 'sass-loader' },
          {
            loader: 'sass-resources-loader',
            options: {
              resources: [
                './pgadmin/static/scss/resources/pgadmin.resources.scss',
              ],
            },
          },
        ],
      },
      {
        test: /\.css$/,
        use: [
          {
            loader: MiniCssExtractPlugin.loader,
            options: {
              publicPath: '',
            },
          },
          'css-loader',
          {
            loader: 'postcss-loader',
            options: {
              postcssOptions: () => ({
                plugins: [require('autoprefixer')()],
              }),
            },
          },
        ],
      },
    ],
    // Prevent module from parsing through webpack, helps in reducing build time
    noParse: [/moment.js/],
  },
  resolve: {
    alias: webpackShimConfig.resolveAlias,
    modules: ['node_modules', '.'],
    extensions: ['.js', '.jsx'],
    unsafeCache: true,
    fallback: {
      fs: false,
    },
  },
  // Watch mode Configuration: After initial build, webpack will watch for
  // changes in files and compiles only files which are changed,
  // if watch is set to True
  // Reference: https://webpack.js.org/configuration/watch/#components/sidebar/sidebar.jsx
  watchOptions: {
    aggregateTimeout: 300,
    poll: 1000,
    ignored: /node_modules/,
  },
  // Webpack 4: uglifyPlugin moved from plugins to optimization
  optimization: {
    minimizer: [
      new TerserPlugin({
        parallel: true,
        extractComments: true,
        terserOptions: {
          compress: true,
        },
      }),
    ],
  },
  // Define list of Plugins used in Production or development mode
  // Ref:https://webpack.js.org/concepts/plugins/#components/sidebar/sidebar.jsx

  // Helps in minimising the `React' production bundle. Bundle only code
  // requires in production mode. React keeps the code conditional
  // based on 'NODE_ENV' variable. [used only in production]
  plugins: PRODUCTION
    ? [
      extractStyle,
      providePlugin,
      new webpack.DefinePlugin({
        'process.env.NODE_ENV': JSON.stringify('production'),
      }),
    ]
    : [
      extractStyle,
      providePlugin,
      new webpack.DefinePlugin({
        'process.env.NODE_ENV': JSON.stringify('development'),
      }),
      sourceMapDevToolPlugin,
    ],
};

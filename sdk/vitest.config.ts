import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'node',
    globals: false,
    // FCL and some deps ship ESM — transform them so vitest (CJS mode) can handle them
    server: {
      deps: {
        inline: [
          '@onflow/fcl',
          '@onflow/types',
          '@onflow/sdk',
          '@onflow/config',
          '@onflow/util-invariant',
          '@onflow/util-logger',
          '@onflow/util-uid',
          '@onflow/rlp',
        ],
      },
    },
  },
})

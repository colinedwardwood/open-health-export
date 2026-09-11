SEC-16: encode destination scope metric sets in canonical metric-ID order so
persisted scope payloads remain byte-identical across processes with different
Swift hash seeds. Decoding now also routes through the validated initializer.

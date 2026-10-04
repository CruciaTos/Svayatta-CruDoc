#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "openjpeg.h"

#if _WIN32
#define FFI_EXPORT __declspec(dllexport)
#else
#define FFI_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

typedef struct { const uint8_t* data; OPJ_SIZE_T len; OPJ_SIZE_T pos; } mem_src;

static OPJ_SIZE_T mem_read(void* buf, OPJ_SIZE_T n, void* user) {
  mem_src* s = (mem_src*)user;
  if (s->pos >= s->len) return (OPJ_SIZE_T)-1;
  OPJ_SIZE_T left = s->len - s->pos;
  if (n > left) n = left;
  memcpy(buf, s->data + s->pos, n);
  s->pos += n;
  return n;
}

static OPJ_OFF_T mem_skip(OPJ_OFF_T n, void* user) {
  mem_src* s = (mem_src*)user;
  if (n < 0) {
    if ((OPJ_SIZE_T)(-n) > s->pos) n = -(OPJ_OFF_T)s->pos;
  } else if ((OPJ_SIZE_T)n > s->len - s->pos) {
    n = (OPJ_OFF_T)(s->len - s->pos);
  }
  s->pos += n;
  return n;
}

static OPJ_BOOL mem_seek(OPJ_OFF_T n, void* user) {
  mem_src* s = (mem_src*)user;
  if (n < 0 || (OPJ_SIZE_T)n > s->len) return OPJ_FALSE;
  s->pos = (OPJ_SIZE_T)n;
  return OPJ_TRUE;
}

/* Decodes a raw JPEG 2000 / HTJ2K codestream, first component only.
   reduce = number of resolution levels to drop (0 = full, 1 = half).
   Returns 0 on success; *out_pixels must be freed with crudoc_j2k_free. */
FFI_EXPORT int32_t crudoc_j2k_decode(const uint8_t* data, int64_t len, int32_t reduce,
                                     int32_t** out_pixels, int32_t* out_w, int32_t* out_h,
                                     int32_t* out_prec, int32_t* out_signed) {
  mem_src src = {data, (OPJ_SIZE_T)len, 0};
  opj_image_t* image = NULL;
  int32_t rc = 0;
  opj_stream_t* stream = opj_stream_create(OPJ_J2K_STREAM_CHUNK_SIZE, OPJ_TRUE);
  if (!stream) return 1;
  opj_stream_set_user_data(stream, &src, NULL);
  opj_stream_set_user_data_length(stream, (OPJ_UINT64)len);
  opj_stream_set_read_function(stream, mem_read);
  opj_stream_set_skip_function(stream, mem_skip);
  opj_stream_set_seek_function(stream, mem_seek);

  opj_codec_t* codec = opj_create_decompress(OPJ_CODEC_J2K);
  opj_dparameters_t params;
  opj_set_default_decoder_parameters(&params);
  params.cp_reduce = (OPJ_UINT32)reduce;

  if (!opj_setup_decoder(codec, &params)) { rc = 2; goto done; }
  opj_decoder_set_strict_mode(codec, OPJ_FALSE);  /* preview stream is cut short */
  if (!opj_read_header(stream, codec, &image)) { rc = 3; goto done; }
  if (!opj_decode(codec, stream, image)) { rc = 4; goto done; }
  opj_end_decompress(codec, stream);  /* may complain on a cut stream; ignore */
  if (image->numcomps < 1) { rc = 5; goto done; }
  {
    opj_image_comp_t* c = &image->comps[0];
    size_t n = (size_t)c->w * (size_t)c->h;
    int32_t* px = (int32_t*)malloc(n * sizeof(int32_t));
    if (!px) { rc = 6; goto done; }
    memcpy(px, c->data, n * sizeof(int32_t));
    *out_pixels = px;
    *out_w = (int32_t)c->w;
    *out_h = (int32_t)c->h;
    *out_prec = (int32_t)c->prec;
    *out_signed = (int32_t)c->sgnd;
  }
done:
  if (image) opj_image_destroy(image);
  opj_destroy_codec(codec);
  opj_stream_destroy(stream);
  return rc;
}

FFI_EXPORT void crudoc_j2k_free(int32_t* p) { free(p); }
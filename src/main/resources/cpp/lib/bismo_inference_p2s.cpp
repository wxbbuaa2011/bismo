#include "bismo_inference_internal.hpp"
#include "gemmbitserial/test/testhelpers.hpp"
#include <string>
namespace bismo_inference {
uint32_t accel_p2s_bitpar_buffer;

// hardware-accelerated 8-bit-parallel to bit-serial conversion
// the 8-bit is only the container datatype, can specify a smaller number
// of actual bits for the conversion
void p2s(
  const uint8_t * host_buf_src,   // input matrix buffer (source)
  uint32_t accel_buf_dst,         // output matrix buffer (destination)
  size_t nrows, size_t ncols,     // matrix size
  size_t nbits,                   // actual bits per element in source matrix
  bool issigned,                  // whether source matrix is signed
  bool zeropad                    // use zero instead of random padding
) {
  // the p2s accelerator requires an aligned number of columns
  size_t ncols_a = gemmbitserial::alignTo(ncols, P2S_ALIGN);
  size_t nbytes_aligned_row = ncols_a * sizeof(uint8_t);
  size_t nbytes_row = ncols * sizeof(uint8_t);
  size_t nbytes_aligned = nrows * ncols_a * sizeof(uint8_t);
  const size_t nbytes_bitser = (nrows * ncols_a * nbits) / 8;
  if(nbytes_aligned > BISMORT_P2S_BITPAR_BYTES) {
    throw "Insufficient p2s bit-parallel buffer size";
  }
  if(issigned) {
    throw "P2S accelerator does not yet support signed import";
  }
  // clean the p2s buffer if desired
  if(zeropad) {
    // hand in a "cleanly padded" buffer to p2s
    uint8_t * in_clean = new uint8_t[nbytes_aligned];
    memset(in_clean, 0, nbytes_aligned);
    platform->copyBufferHostToAccel((void *)in_clean, (void *)accel_p2s_bitpar_buffer, nbytes_aligned);
    delete [] in_clean;
  }
  // aligned copy the bit-parallel matrix into the accelerator
  for(size_t r = 0; r < nrows; r++) {
    platform->copyBufferHostToAccel(
      (void *)&host_buf_src[r * nbytes_row],
      (void *)(accel_p2s_bitpar_buffer + (r * nbytes_aligned_row)),
      nbytes_row);
  }
  // setup and call the p2s hardware accelerator
  acc->setup_p2s((void *)accel_p2s_bitpar_buffer, nbytes_bitser, (void *) accel_buf_dst, nrows, ncols_a, nbits);
  uint32_t cycles = acc->p2s_exec_and_wait();
  instrumentationData["run_p2s"] = (float) cycles;
}

bool selftest_p2s() {
  size_t nbits = 3;
  size_t nrows = 200;
  size_t ncols = 200;
  bool issigned = false;
  string test_name = "p2s_" + to_string(nrows) + "x" + to_string(ncols) + "_" + to_string(nbits) +"b_" + (issigned ? "s" : "u");
  cout << "Starting test:" << test_name << endl;
  uint8_t * mat_bp = new uint8_t[nrows * ncols];
  gemmbitserial::generateRandomVector(nbits, nrows*ncols, mat_bp);
  gemmbitserial::BitSerialMatrix mat_bs = gemmbitserial::BitSerialMatrix::alloc(
    nbits, nrows, ncols, issigned, 1, P2S_ALIGN
  );
  mat_bs.importRegular(mat_bp);
  size_t nbytes_bitser = mat_bs.wordsPerBitplane() * nbits * sizeof(PackedBitGroupType);
  uint32_t accel_buf = (uint32_t)(uint64_t)platform->allocAccelBuffer(nbytes_bitser);
  // call p2s with forced zero-padding
  p2s(mat_bp, accel_buf, nrows, ncols, nbits, issigned, true);
  // copy result back to host
  uint8_t * accel_mat_bs = new uint8_t[nbytes_bitser];
  platform->copyBufferAccelToHost((void *)accel_buf, accel_mat_bs, nbytes_bitser);
  bool ret = (memcmp(accel_mat_bs, mat_bs.data, nbytes_bitser) == 0);
  /*if(!ret) {
    for(size_t i = 0; i < nbytes_bitser; i++) {
      if(accel_mat_bs[i] != ((uint8_t*)mat_bs.data)[i]) {
        cout << i << "\t" <<  hex << (int)accel_mat_bs[i] << "\t" << (int)((uint8_t*)mat_bs.data)[i] << dec << endl;
      }
    }
  }*/
  cout << test_name << "\t" << ret << endl;
  platform->deallocAccelBuffer((void *)accel_buf);
  delete [] accel_mat_bs;
  delete [] mat_bp;
  return ret;
}
}

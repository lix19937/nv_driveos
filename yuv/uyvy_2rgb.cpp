/**************************************************************
 * @Copyright: 2021-2022 Copyright
 * @Author: lix
 * @Date: 2022-01-10 13:35:47
 * @Last Modified by: lix
 * @Last Modified time: 2022-01-14 14:32:53
 **************************************************************/

//  modules/imgproc/src/color_yuv.simd.hpp
//  modules/imgproc/src/color.cpp

#include <stdint.h>
#include <algorithm>
#include "opencv2/opencv.hpp"

static const int ITUR_BT_601_CY = 1220542;
static const int ITUR_BT_601_CUB = 2116026;
static const int ITUR_BT_601_CUG = -409993;
static const int ITUR_BT_601_CVG = -852492;
static const int ITUR_BT_601_CVR = 1673527;
static const int ITUR_BT_601_SHIFT = 20;

// YUV422toRGB8Invoker
// cv::cvtColor(im, cv::COLOR_YUV2BGR_UYVY)

// R = 1.164(Y - 16) + 1.596(V - 128)
// G = 1.164(Y - 16) - 0.813(V - 128) - 0.391(U - 128)
// B = 1.164(Y - 16)                  + 2.018(U - 128)
//                   ===>
// R = (1220542(Y - 16) + 1673527(V - 128)                  + (1 << 19)) >> 20
// G = (1220542(Y - 16) - 852492(V - 128) - 409993(U - 128) + (1 << 19)) >> 20
// B = (1220542(Y - 16)                  + 2116026(U - 128) + (1 << 19)) >> 20
namespace {

inline void uvToRGBuv(
    const uint8_t u,
    const uint8_t v,
    int& ruv,
    int& guv, // NOLINT
    int& buv) { // NOLINT
  int uu, vv;
  uu = static_cast<int>(u) - 128;
  vv = static_cast<int>(v) - 128;
  ruv = (1 << (ITUR_BT_601_SHIFT - 1)) + ITUR_BT_601_CVR * vv;
  guv = (1 << (ITUR_BT_601_SHIFT - 1)) + ITUR_BT_601_CVG * vv + ITUR_BT_601_CUG * uu;
  buv = (1 << (ITUR_BT_601_SHIFT - 1)) + ITUR_BT_601_CUB * uu;
}

inline void yRGBuvToRGBA(
    const uint8_t vy,
    const int ruv,
    const int guv,
    const int buv,
    uint8_t& r,
    uint8_t& g, // NOLINT
    uint8_t& b, // NOLINT
    uint8_t& a) { // NOLINT
  int yy = static_cast<int>(vy);
  int y = std::max(0, yy - 16) * ITUR_BT_601_CY;

  auto saturate_cast = [](const int& v) { return (uint8_t)((unsigned)v <= UCHAR_MAX ? v : v > 0 ? UCHAR_MAX : 0); };

  r = saturate_cast((y + ruv) >> ITUR_BT_601_SHIFT);
  g = saturate_cast((y + guv) >> ITUR_BT_601_SHIFT);
  b = saturate_cast((y + buv) >> ITUR_BT_601_SHIFT);
  a = uint8_t(0xff);
}

template <int bIdx, int dcn, bool is420>
inline void yuv42xxp2rgb8(
    const uint8_t u,
    const uint8_t v,
    const uint8_t vy01,
    const uint8_t vy11,
    const uint8_t vy02,
    const uint8_t vy12,
    uint8_t* row1,
    uint8_t* row2) {
  int ruv, guv, buv;
  uvToRGBuv(u, v, ruv, guv, buv);

  uint8_t r00, g00, b00, a00;
  uint8_t r01, g01, b01, a01;

  yRGBuvToRGBA(vy01, ruv, guv, buv, r00, g00, b00, a00);
  yRGBuvToRGBA(vy11, ruv, guv, buv, r01, g01, b01, a01);

  row1[2 - bIdx] = r00;
  row1[1] = g00;
  row1[bIdx] = b00;
  if (dcn == 4) {
    row1[3] = a00;
  }

  row1[dcn + 2 - bIdx] = r01;
  row1[dcn + 1] = g01;
  row1[dcn + 0 + bIdx] = b01;
  if (dcn == 4) {
    row1[7] = a01;
  }

  if (is420) {
    uint8_t r10, g10, b10, a10;
    uint8_t r11, g11, b11, a11;

    yRGBuvToRGBA(vy02, ruv, guv, buv, r10, g10, b10, a10);
    yRGBuvToRGBA(vy12, ruv, guv, buv, r11, g11, b11, a11);

    row2[2 - bIdx] = r10;
    row2[1] = g10;
    row2[bIdx] = b10;
    if (dcn == 4) {
      row2[3] = a10;
    }

    row2[dcn + 2 - bIdx] = r11;
    row2[dcn + 1] = g11;
    row2[dcn + 0 + bIdx] = b11;
    if (dcn == 4) {
      row2[7] = a11;
    }
  }
}
} // namespace

template <int bIdx, int uIdx, int yIdx, int dcn>
void yuv422p2rgb(
    uint8_t* dst_data, /* rgb/bgr */
    size_t stride, /* width */
    size_t dst_step, /* 3*width */
    size_t src_step, /* 2*width */
    int width,
    int height,
    const uint8_t* src_data) {
  ////////// NOTE  dcn = 3;  // rgb/bgr is 3, rgba/bgra is 4
  //////////       bIdx = 2; // rgb is 2, bgr is 0   `B` location index
  /*
        case COLOR_YUV2RGB_UYVY: case COLOR_YUV2BGR_UYVY: case COLOR_YUV2RGBA_UYVY: case COLOR_YUV2BGRA_UYVY:
        case COLOR_YUV2RGB_YUY2: case COLOR_YUV2BGR_YUY2: case COLOR_YUV2RGB_YVYU: case COLOR_YUV2BGR_YVYU:
        case COLOR_YUV2RGBA_YUY2: case COLOR_YUV2BGRA_YUY2: case COLOR_YUV2RGBA_YVYU: case COLOR_YUV2BGRA_YVYU:
            //http://www.fourcc.org/yuv.php#UYVY
            //http://www.fourcc.org/yuv.php#YUY2
            //http://www.fourcc.org/yuv.php#YVYU
            {
                int ycn  = (code==COLOR_YUV2RGB_UYVY || code==COLOR_YUV2BGR_UYVY ||
                            code==COLOR_YUV2RGBA_UYVY || code==COLOR_YUV2BGRA_UYVY) ? 1 : 0;
                cvtColorOnePlaneYUV2BGR(_src, _dst, dcn, swapBlue(code), uIndex(code), ycn);
                break;
            }
  */
  //
  // for COLOR_YUV2RGB_UYVY,                      bIdx=2, uIdx=0, yIdx=1, dcn=3
  // for COLOR_YUV2BGR_UYVY,                      bIdx=0, uIdx=0, yIdx=1, dcn=3
  // for COLOR_YUV2BGR_YUY2 (COLOR_YUV2BGR_YUYV)  bIdx=0, uIdx=1, yIdx=0, dcn=3
  const int rangeBegin{0};
  const int rangeEnd{height};

  const int uidx = 1 - yIdx + uIdx * 2;
  const int vidx = (2 + uidx) % 4;
  const uchar* yuv_src = src_data + rangeBegin * src_step; ////// -----------

  for (int j = rangeBegin; j < rangeEnd; j++, yuv_src += src_step) {
    uchar* row = dst_data + dst_step * j; ////// +++++++++++
    int i = 0;

    for (; i < 2 * width; i += 4, row += dcn * 2) { ////
      uchar u = yuv_src[i + uidx];
      uchar v = yuv_src[i + vidx];

      uchar vy0 = yuv_src[i + yIdx];
      uchar vy1 = yuv_src[i + yIdx + 2];

     // ref cvtYuv42xxp2RGB8 from opencv4.9.0   modules/imgproc/src/color_yuv.simd.hpp     
      yuv42xxp2rgb8<bIdx, dcn, false>(u, v, vy0, vy1, 0, 0, row, (uchar*)(0));
    }
  }
}

int main() {
  auto img_bgr = cv::imread("debug.png");
  // cv::imshow("original", img_bgr);
  // cv::waitKey(0);

  int w = img_bgr.cols;
  int h = img_bgr.rows;
  int c = img_bgr.channels();

  ////// Convert from BGR to YUV, Just to get YUV422 data
  cv::Mat img_yuv422(h, w, CV_8UC2, cv::Scalar::all(0));
  cv::cvtColor(img_bgr, img_yuv422, cv::COLOR_BGR2YUV_UYVY);

  ////// YUV422 TO BGR
  cv::Mat img_bgr_gt;
  cv::cvtColor(img_yuv422, img_bgr_gt, cv::COLOR_YUV2BGR_UYVY);
  // cv::imshow("img_bgr_gt", img_bgr_gt);cv::waitKey(0);
  cv::imwrite("img_bgr_gt.png", img_bgr_gt);

  ////// Byself
  cv::Mat img_bgr_ref(h, w, CV_8UC3, cv::Scalar::all(0));
  yuv422p2rgb<0, 0, 1, 3>(img_bgr_ref.data, w, 3 * w, 2 * w, w, h, img_yuv422.data);

  cv::imwrite("img_bgr_ref.png", img_bgr_ref);
  return 0;
}

/*
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/mnt/d/workspace/opencv-4.9.0/build/install_local/lib
g++ -std=c++14 -O2 ./yuv422p2rgb.cpp  -lopencv_core -lopencv_imgproc -lopencv_highgui -lopencv_imgcodecs \
-I/mnt/d/workspace/opencv-4.9.0/build/install_local/include/opencv4 \
-L/mnt/d/workspace/opencv-4.9.0/build/install_local/lib


*/

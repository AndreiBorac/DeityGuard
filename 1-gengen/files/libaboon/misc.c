/*
  libaboon/misc.c
  copyright (c) 2017 by andrei borac
*/

static uintptr_t lb_misc_narrow_64_ptr(uint64_t x)
{
  uintptr_t retv = ((uintptr_t)(x));
  LB_ASSURE(retv == x);
  return retv;
}

static uint32_t lb_misc_narrow_ptr_32(uintptr_t x)
{
  uint32_t retv = ((uint32_t)(x));
  LB_ASSURE(retv == x);
  return retv;
}

static uint64_t lb_misc_div_64_by_32_exact(uint64_t divend, uint32_t divsor)
{
  uint64_t divquo;
  
  LB_ASSURE_EQZ(lb_div_64_by_32(divend, divsor, (&(divquo))));
  
  return divquo;
}

static char* lb_misc_strdupmem(char const* mem, uintptr_t len, lb_alloc_t* ac)
{
  char* tmp = ((char*)(lb_alloc(ac, (len + 1))));
  lb_memcpy(tmp, mem, len);
  tmp[len] = '\0';
  return tmp;
}

static char* lb_misc_strdup(char const* str, lb_alloc_t* ac)
{
  return lb_misc_strdupmem(str, lb_strlen(str), ac);
}

static char* lb_misc_strdup_append(char const* str, char const* app, lb_alloc_t* ac)
{
  uintptr_t len_str = lb_strlen(str);
  uintptr_t len_app = lb_strlen(app);
  char* tmp = ((char*)(lb_alloc(ac, (len_str + len_app + 1))));
  lb_memcpy(tmp, str, len_str);
  lb_memcpy((tmp + len_str), app, (len_app + 1));
  return tmp;
}

static void lb_misc_strdup_free(char* str, lb_alloc_t* ac)
{
  uintptr_t len = lb_strlen(str);
  lb_alloc_free(ac, str, (len + 1));
}

static char const* lb_misc_getenv(char const* const* envp, char const* key LB_UNUSED)
{
  uintptr_t len = lb_strlen(key);
  
  LB_PV(len);
  
  char const* const* walk = envp;
  
  while (*walk) {
    char const* pair = *walk;
    
    LB_PV(walk);
    LB_PV(pair);
    LB_DG("sssss", "key='", key, "', pair='", pair, "'\n");
    //LB_PV(lbi_memcmp(LB_U(pair), LB_U(key), (len+1)));
    
    if (lb_memcmp(pair, key, len)) {
      if (pair[len] == '=') {
        return (pair + len + 1);
      }
    }
    
    walk++;
  }
  
  return NULL;
}

#define LB_MISC_XCHG(a, b) ({ __typeof__(a) LB_MISC_XCHG__A = (a); (a) = (b); (b) = LB_MISC_XCHG__A; })

static void lbi_misc_qsort(void const** A, void const** Z, bool (*cmp)(void const*, void const*))
{
  while ((Z - A) > 1) {
    /*
      quicksort is a bit tricky. the basic idea of just partitioning
      into < and >= partitions and recursing on each isn't guaranteed
      to terminate, because everything can end up in the >= part.
      
      the key to termination is to make sure at least one element
      drops out.
      
      the element that drops out must be equal to the pivot, so that
      it can be >= everything in the < part and <= to everything in
      the >= part. most simply, this element can be the pivot, which
      should be inserted between the < and the >= parts.
      
      so as we build up the regions we keep the pivot at the start of
      the array and later exchange it with the last element in the <
      part.
    */
    void const* pivot = *A;
    
    /* S points to the first element in the >= part */
    void const** S = A+1;
    
    for (void const** I = S; I < Z; I++) {
      if (cmp(*I, pivot)) {
        /* when *I < pivot */
        /* we must exchange with the first element in the >= part */
        LB_MISC_XCHG(*I, *S);
        /* and shift the >= part over by one */
        S++;
      } else {
        /* when *I >= pivot */
        /* nothing to do, the >= part grows "automatically" */
      }
    }
    
    /* now do the business of exchanging the pivot */
    void const** R = (S - 1);
    *A = *R;
    *R = pivot;
    
    /* recursively sort (>=A, <R) and (>=S, <Z) */
    /* recurse on the smaller partition */
    /* this keeps stack usage always at or below O(log n) */
    if ((R - A) < (Z - S)) {
      lbi_misc_qsort(A, R, cmp);
      A = S; /* loop to sort (>=S, <Z) */
    } else {
      lbi_misc_qsort(S, Z, cmp);
      Z = R; /* loop to sort (>=A, <R) */
    }
  }
}

/*
  cmp should return true iff [arg1] < [arg2] (strictly).
*/
static LB_INLINE void lb_misc_qsort(void const** A, uintptr_t L, bool (*cmp)(void const*, void const*))
{
  lbi_misc_qsort(A, (A + L), cmp);
}

#define LB_MISC_QSORT_VARIANT(s, t)                                     \
  static LB_INLINE void lb_misc_qsort_##s(t** A, uintptr_t L, bool (*cmp)(t const*, t const*)) \
  {                                                                     \
    lb_misc_qsort(((void const**)(A)), L, ((bool (*)(void const*, void const*))(cmp)));   \
  }

/*
  used as the base case of bsearch.
*/
static void const* lbi_misc_bsearch_linear(void const** A, void const** Z, void const* K, bool (*cmp)(void const*, void const*))
{
  /*
    burn forward while *A < K. if there is anything left, it will have
    to be that *A >= K.
  */
  while ((A < Z) && cmp(*A, K)) A++;
  
  /*
    if there is nothing left, we're done.
  */
  if (!(A < Z)) return NULL;
  
  /*
    now we know *A >= K.
  */
  {
    if (cmp(K, *A)) {
      /* when K < *A */
      /* this means *A > K, so no dice */
      return NULL;
    } else {
      /* when K >= *A */
      /* this means *A == K, so return it */
      return *A;
    }
  }
}

static void const* lbi_misc_bsearch(void const** A, void const** Z, void const* K, bool (*cmp)(void const*, void const*))
{
  /*
    must stop loop when there are 3 or fewer elements, otherwise it
    could go on forever in the bottom case.
  */
  while ((Z - A) > 3) {
    void const** M = (A + ((Z - A) >> 1));
    
    if (cmp(*M, K)) {
      /* when *M < K */
      A = M + 1;
    } else {
      /* when *M >= K */
      Z = M + 1;
    }
  }
  
  /*
    we're down to at most 3 elements, to downgrade to linear search to
    finish up.
  */
  return lbi_misc_bsearch_linear(A, Z, K, cmp);
}

/*
  cmp should return true iff [arg1] < [arg2] (strictly).
*/
static LB_INLINE void const* lb_misc_bsearch(void const** A, uintptr_t L, void const* K, bool (*cmp)(void const*, void const*))
{
  return lbi_misc_bsearch(A, (A + L), K, cmp);
}

#define LB_MISC_BSEARCH_VARIANT(s, t)                                   \
  static LB_INLINE t* lb_misc_bsearch_##s(t** A, uintptr_t L, t const* K, bool (*cmp)(t const*, t const*)) \
  {                                                                     \
    return ((t*)(lb_misc_bsearch(((void const**)(A)), L, K, ((bool (*)(void const*, void const*))(cmp))))); \
  }

enum { lbi_misc_lfg_lag_A =  30, };
enum { lbi_misc_lfg_lag_B = 127, };
enum { lbi_misc_lfg_tb_sz = 128, };

LB_TYPEBOTH(lb_misc_lfg_t)
{
  uintptr_t pos;
  uint64_t  arr[lbi_misc_lfg_tb_sz];
};

static void lb_misc_lfg_initialize(lb_misc_lfg_t* rg)
{
  static uint64_t const iv[lbi_misc_lfg_tb_sz] =
    {
      0xdcadffc238b0a901, 0x715bf7856ca3762c, 0x7e8f09576290007b, 0x0e8f7d0439f49a34,
      0x07efbf4191784613, 0xaba3174daeeea2de, 0x02cdc67259fd752a, 0xd476dd563113c374,
      0x2c744ac7139ea25b, 0x7f684d53535abb29, 0x0f227519185e06a4, 0xebc2d13f7dcd7d55,
      0x9fed788f202b1ed7, 0x1ea229e558cfcda7, 0xb52cd31ac8607387, 0xb40d8373dc6aeb90,
      0x328222a73ae4b776, 0x2d0dd6db2c82fba8, 0x4ed106c4354ddf02, 0x6e22cfab35068ba2,
      0xab250087ee9b22ae, 0xbf5c41db323c9581, 0x4fe1f604705666c3, 0x35c77f8b08b719bb,
      0x43bd3d0adac7ee0a, 0x3542817a5ba3c9dc, 0x4ff8946abf2b3e6d, 0x608744add80189d0,
      0x2dc2617f81af73b3, 0x8c5de8e78a1a001e, 0xafb38d71b2f56266, 0x7596268d0cce0b85,
      0xfebe3659e1bfc7be, 0x8e831778348e7a5d, 0xa40e211ce2db488e, 0x361648e92fe881d8,
      0xff86d21901e4c276, 0xd72be9f6afee6398, 0xff34163a8a363c93, 0xd3d149b8bf08d11b,
      0x674473622036b8e4, 0x6a71d1175480b17c, 0x175bbae0efef8d6b, 0x905afc670a811b7e,
      0x8acebc4c78ec31d9, 0x48879e7dc0e1f042, 0xadfd8069fe2504a5, 0x42a261afa3d26b35,
      0xab44133b03697872, 0x8df78be078f54839, 0x8cd5233ff4841988, 0x54a1d22ee271bd06,
      0x6dd70d1a79349ace, 0x9f58b05bf50dc762, 0x306b16c2363df0ce, 0x1c2c594bc12095cc,
      0x24b74c2afd88cd6a, 0x2fd647ebe55735b6, 0x921e869cd297a022, 0x4b09588161c81fa2,
      0x1e39dcda3805904f, 0xeb6688b1586e07f4, 0x31589483461deff8, 0xd8d2d5e18cf3bbe1,
      0x017704197ebadcd6, 0xde5fbd92759e68dd, 0x6b0c39a3f54753aa, 0xff5dbbc88ca69724,
      0x34605060e8bbc2ef, 0x27210b93bf1d4b1f, 0x8037e64c6eb30b7e, 0x3cf1cd83e7252dd7,
      0xce9af6297c72e530, 0x8fb1494cc2e58704, 0xd947c22032b107d9, 0xd997f60a8da61d41,
      0x7ee020d08e52e25d, 0x218015fdda0426a7, 0x3c7f4c7c4dbc8574, 0xaf8b0aceb5361082,
      0x24f0166efdcde132, 0xee70817750434728, 0xde9897bf69e50cdd, 0x09e10568a8cc893b,
      0x18328787500a0b31, 0x8811d5ef21f97785, 0xdfb5390d0a64f452, 0x9e64ca436be547f8,
      0xbd0c693478a48d0b, 0xa2e70ae0721b7c08, 0x82f0b8451ac47d75, 0x8349be3f1da54e3d,
      0x15d5ed0fbeddbcb1, 0x913e35df7fc72cda, 0x5fd4b7d874f1aa3a, 0xe05722b9b04ee3ad,
      0xd09324a3bed48744, 0x43b08763efdfc98a, 0xc55542b90c60ab96, 0x5b759d0f38bb8ebf,
      0x52e683f618f5b279, 0x631da7978cdf48c8, 0x954556dbdf99a7d3, 0xeb36342b06757a13,
      0xda8a61a3e8475537, 0x26b051696382f6ba, 0x14aded969b54aca8, 0x25987fc797b465ea,
      0xc57a909ad45704ac, 0x531f9bc055066b0c, 0x9ebf77551976ab07, 0xc7caece415549c8f,
      0x154b8afc841c6d28, 0xc6b978e7c0af5a68, 0xe53f8239b81e8846, 0xccb4d037f4c6be1a,
      0x97a840a917237c29, 0x3d227072681d1906, 0x89f9a4681aebd8f7, 0xdc5614f22f79ff7d,
      0x5f3f004886a7eac4, 0x8d39fc34b2da5fab, 0xb25c8c11773193b6, 0xaf53b54231de2cec,
      0x569e47210b8000a3, 0x32b6d8fdd184981e, 0x63ddcbebd46d5df8, 0xc157e1afd0c99083
    };
  
  rg->pos = -1UL;
  lb_memcpy(rg->arr, iv, sizeof(rg->arr));
}

static LB_INLINE uintptr_t lbi_misc_lfg_index(uintptr_t x)
{
  return (x & (lbi_misc_lfg_tb_sz - 1));
}

static LB_INLINE uint64_t lb_misc_lfg_next(lb_misc_lfg_t* rg)
{
  rg->pos++;
  
  return
    ( rg->arr[lbi_misc_lfg_index(rg->pos)] =
     (rg->arr[lbi_misc_lfg_index(rg->pos - lbi_misc_lfg_lag_A)] +
      rg->arr[lbi_misc_lfg_index(rg->pos - lbi_misc_lfg_lag_B)]));
}

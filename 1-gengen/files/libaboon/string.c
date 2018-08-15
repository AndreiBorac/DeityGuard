/*
  libaboon/string.c
  copyright (c) 2017 by andrei borac
*/

static uintptr_t lb_strlen(char const* str)
{
  char const* ori = str;
  
  while (*(str++));
  
  return (LB_U(str - ori) - 1);
}

static bool lb_strcmp(char const* src1, char const* src2)
{
  uintptr_t len1 = lb_strlen(src1);
  uintptr_t len2 = lb_strlen(src2);
  
  return ((len1 == len2) && (lb_memcmp(src1, src2, len1)));
}

static void lb_strnrev(char* str, uintptr_t len)
{
  char* lhs = str;
  char* rhs = (str + len - 1);
  
  while (lhs < rhs) {
    char tmp = *lhs;
    *lhs     = *rhs;
    *rhs     =  tmp;
    
    lhs++;
    rhs--;
  }
}

static void lb_strrev(char* str)
{
  lb_strnrev(str, lb_strlen(str));
}

#if 0

static uint64_t lb_atou_64(char const* str)
{
  uint64_t val = 0;
  
  LB_ASSURE((*str));
  
  /*
    here we limit to numbers with 18 or fewer digits. 2^63-1 is 19
    digits while 2^64-1 is 20 digits. so we leave quite a large
    unusable safety zone.
  */
  LB_ASSURE((lb_strlen(str) <= 18));
  
  {
    char chr;
    
    while ((chr = *(str++))) {
      LB_ASSURE((('0' <= chr) && (chr <= '9')));
      uintptr_t inc = LB_U((chr - '0'));
      uint64_t val_next = (((val << 3) + (val << 1)) + inc);
      val = val_next;
    }
  }
  
  return val;
}

#endif

static uint64_t lb_atou_64(char const* str)
{
  uint64_t val = 0;
  
  LB_ASSURE((*str));
  
  {
    char chr;
    
    while ((chr = *(str++))) {
      LB_ASSURE((('0' <= chr) && (chr <= '9')));
      uintptr_t inc = LB_U((chr - '0'));
      
      /*
        make sure it's not an overflow to multiply by eight.
      */
      uint64_t val_x8;
      LB_ASSURE((((val_x8 = (val << 3)) >> 3) == val));
      
      /*
        since adding seven times the value does not overflow, there is
        no way adding two times the value plus a small constant could
        possibly -overwrap-. so we can accurately detect overflow
        here.
      */
      uint64_t val_x10i;
      LB_ASSURE(((val_x10i = (val_x8 + (val << 1) + inc)) >= val_x8));
      
      val = val_x10i;
    }
  }
  
  return val;
}

static uintptr_t lb_utoa_64_sz(uint64_t val)
{
  uintptr_t pos = 0;
  
  if (val > 0) {
    while (val > 0) {
      pos++; lb_div_64_by_32(val, 10, (&val));
    }
  } else {
    pos++;
  }
  
  return pos;
}

static uintptr_t lb_utoa_64(char* str, uint64_t val)
{
  uintptr_t pos = 0;
  
  if (val > 0) {
    while (val > 0) {
      str[pos++] = ((char)('0' + lb_div_64_by_32(val, 10, (&val))));
    }
  } else {
    str[pos++] = '0';
  }
  
  str[pos] = '\0';
  
  lb_strnrev(str, pos);
  
  return pos;
}

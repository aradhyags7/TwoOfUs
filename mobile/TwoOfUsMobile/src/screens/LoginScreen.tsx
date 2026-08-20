import React, {useState, useRef} from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  Animated,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
} from 'react-native';

export default function LoginScreen({navigation}: any) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [emailFocused, setEmailFocused] = useState(false);
  const [passFocused, setPassFocused] = useState(false);
  const [showPass, setShowPass] = useState(false);
  const [error, setError] = useState('');
  const [emailValid, setEmailValid] = useState<boolean | null>(null);

  const shakeAnim = useRef(new Animated.Value(0)).current;
  const fadeLogo = useRef(new Animated.Value(0)).current;
  const slideCard = useRef(new Animated.Value(50)).current;
  const fadeCard = useRef(new Animated.Value(0)).current;
  const logoScale = useRef(new Animated.Value(0.8)).current;
  const errorOpacity = useRef(new Animated.Value(0)).current;
  const buttonScale = useRef(new Animated.Value(1)).current;
  const biometricPulse = useRef(new Animated.Value(1)).current;
  const orb1 = useRef(new Animated.Value(0)).current;
  const orb2 = useRef(new Animated.Value(0)).current;

  React.useEffect(() => {
    Animated.parallel([
      Animated.spring(logoScale, {toValue: 1, tension: 60, friction: 8, useNativeDriver: true}),
      Animated.timing(fadeLogo, {toValue: 1, duration: 800, useNativeDriver: true}),
      Animated.timing(fadeCard, {toValue: 1, duration: 700, delay: 250, useNativeDriver: true}),
      Animated.spring(slideCard, {toValue: 0, tension: 50, friction: 9, delay: 250, useNativeDriver: true}),
    ]).start();

    // Floating orb animations
    Animated.loop(
      Animated.sequence([
        Animated.timing(orb1, {toValue: 1, duration: 4000, useNativeDriver: true}),
        Animated.timing(orb1, {toValue: 0, duration: 4000, useNativeDriver: true}),
      ])
    ).start();
    Animated.loop(
      Animated.sequence([
        Animated.timing(orb2, {toValue: 1, duration: 5500, useNativeDriver: true}),
        Animated.timing(orb2, {toValue: 0, duration: 5500, useNativeDriver: true}),
      ])
    ).start();

    // Biometric pulse
    Animated.loop(
      Animated.sequence([
        Animated.timing(biometricPulse, {toValue: 1.08, duration: 900, useNativeDriver: true}),
        Animated.timing(biometricPulse, {toValue: 1, duration: 900, useNativeDriver: true}),
      ])
    ).start();
  }, []);

  const shake = () => {
    Animated.sequence([
      Animated.timing(shakeAnim, {toValue: 12, duration: 55, useNativeDriver: true}),
      Animated.timing(shakeAnim, {toValue: -12, duration: 55, useNativeDriver: true}),
      Animated.timing(shakeAnim, {toValue: 8, duration: 55, useNativeDriver: true}),
      Animated.timing(shakeAnim, {toValue: -8, duration: 55, useNativeDriver: true}),
      Animated.timing(shakeAnim, {toValue: 0, duration: 55, useNativeDriver: true}),
    ]).start();
  };

  const animateError = (msg: string) => {
    setError(msg);
    errorOpacity.setValue(0);
    Animated.timing(errorOpacity, {toValue: 1, duration: 250, useNativeDriver: true}).start();
    shake();
  };

  const pressIn = () => {
    Animated.spring(buttonScale, {toValue: 0.96, useNativeDriver: true, tension: 200}).start();
  };

  const pressOut = () => {
    Animated.spring(buttonScale, {toValue: 1, useNativeDriver: true, tension: 200}).start();
  };

  const validateEmail = (val: string) => {
    setEmail(val);
    if (val.length > 4) {
      setEmailValid(/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(val));
    } else {
      setEmailValid(null);
    }
  };

  const handleLogin = async () => {
    if (!email || !password) {
      animateError('Please fill in all fields');
      return;
    }
    if (emailValid === false) {
      animateError('Please enter a valid email address');
      return;
    }
    setError('');
    setLoading(true);
    await new Promise<void>(resolve =>
  setTimeout(() => resolve(), 1400),
   );
    setLoading(false);
    navigation.replace('Chats');
  };

  const orb1TranslateY = orb1.interpolate({inputRange: [0, 1], outputRange: [0, -18]});
  const orb2TranslateY = orb2.interpolate({inputRange: [0, 1], outputRange: [0, 14]});

  return (
    <KeyboardAvoidingView
      style={{flex: 1}}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
      <ScrollView
        style={styles.container}
        contentContainerStyle={styles.scroll}
        keyboardShouldPersistTaps="handled">

        {/* Background orbs */}
        <Animated.View
          style={[styles.orb, styles.orb1, {transform: [{translateY: orb1TranslateY}]}]}
          pointerEvents="none"
        />
        <Animated.View
          style={[styles.orb, styles.orb2, {transform: [{translateY: orb2TranslateY}]}]}
          pointerEvents="none"
        />

        <Animated.View style={{opacity: fadeLogo, transform: [{scale: logoScale}], alignItems: 'center', marginBottom: 32}}>
          <View style={styles.logoIconWrap}>
            <Text style={styles.logoIcon}>💞</Text>
          </View>
          <Text style={styles.logo}>TwoOfUs</Text>
          <Text style={styles.logoTagline}>Your story, together</Text>
        </Animated.View>

        <Animated.View
          style={[
            styles.card,
            {
              opacity: fadeCard,
              transform: [
                {translateY: slideCard},
                {translateX: shakeAnim},
              ],
            },
          ]}>

          <Text style={styles.title}>Welcome back</Text>
          <Text style={styles.subtitle2}>Sign in to continue your story</Text>

          {!!error && (
            <Animated.View style={[styles.errorBanner, {opacity: errorOpacity}]}>
              <Text style={styles.errorIcon}>⚠️</Text>
              <Text style={styles.errorText}>{error}</Text>
            </Animated.View>
          )}

          {/* Email Field */}
          <View style={[styles.inputWrap, emailFocused && styles.inputFocused, emailValid === false && styles.inputError]}>
            <View style={styles.labelRow}>
              <Text style={[styles.inputLabel, emailValid === false && {color: '#F87171'}]}>Email</Text>
              {emailValid === true && <Text style={styles.checkMark}>✓</Text>}
              {emailValid === false && <Text style={styles.crossMark}>✗</Text>}
            </View>
            <TextInput
              style={styles.input}
              placeholder="you@example.com"
              placeholderTextColor="#2D4060"
              value={email}
              onChangeText={validateEmail}
              onFocus={() => setEmailFocused(true)}
              onBlur={() => setEmailFocused(false)}
              keyboardType="email-address"
              autoCapitalize="none"
            />
          </View>

          {/* Password Field */}
          <View style={[styles.inputWrap, passFocused && styles.inputFocused]}>
            <Text style={styles.inputLabel}>Password</Text>
            <View style={styles.passRow}>
              <TextInput
                style={[styles.input, {flex: 1}]}
                placeholder="••••••••"
                placeholderTextColor="#2D4060"
                value={password}
                onChangeText={setPassword}
                secureTextEntry={!showPass}
                onFocus={() => setPassFocused(true)}
                onBlur={() => setPassFocused(false)}
              />
              <TouchableOpacity onPress={() => setShowPass(v => !v)} style={styles.eyeBtn}>
                <Text style={styles.eyeText}>{showPass ? '🙈' : '👁️'}</Text>
              </TouchableOpacity>
            </View>
          </View>

          <TouchableOpacity style={styles.forgotWrap}>
            <Text style={styles.forgot}>Forgot password?</Text>
          </TouchableOpacity>

          {/* Sign In Button */}
          <Animated.View style={{transform: [{scale: buttonScale}]}}>
            <TouchableOpacity
              style={[styles.button, loading && styles.buttonLoading]}
              onPress={handleLogin}
              onPressIn={pressIn}
              onPressOut={pressOut}
              activeOpacity={1}
              disabled={loading}>
              {loading ? (
                <View style={styles.loadingRow}>
                  <ActivityIndicator color="white" size="small" />
                  <Text style={[styles.buttonText, {marginLeft: 10}]}>Signing in…</Text>
                </View>
              ) : (
                <Text style={styles.buttonText}>Sign In</Text>
              )}
            </TouchableOpacity>
          </Animated.View>

          {/* Biometric */}
          <View style={styles.biometricRow}>
            <View style={styles.dividerLine} />
            <Text style={styles.dividerText}>or</Text>
            <View style={styles.dividerLine} />
          </View>
          <View style={styles.biometricWrap}>
            <Animated.View style={{transform: [{scale: biometricPulse}]}}>
              <TouchableOpacity style={styles.biometricBtn} activeOpacity={0.8}>
                <Text style={styles.biometricIcon}>🪪</Text>
                <Text style={styles.biometricText}>Use Biometrics</Text>
              </TouchableOpacity>
            </Animated.View>
          </View>

          <View style={styles.divider}>
            <View style={styles.dividerLine} />
            <Text style={styles.dividerText}>new here?</Text>
            <View style={styles.dividerLine} />
          </View>

          <TouchableOpacity
            style={styles.registerBtn}
            onPress={() => navigation.navigate('Register')}
            activeOpacity={0.8}>
            <Text style={styles.registerText}>Create a new account →</Text>
          </TouchableOpacity>
        </Animated.View>

        <Text style={styles.legalText}>By signing in you agree to our Terms & Privacy Policy</Text>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {flex: 1, backgroundColor: '#060E1A'},
  scroll: {flexGrow: 1, justifyContent: 'center', padding: 24, paddingBottom: 48},

  orb: {position: 'absolute', borderRadius: 999},
  orb1: {
    width: 280, height: 280,
    backgroundColor: 'rgba(79,140,255,0.07)',
    top: -60, right: -80,
  },
  orb2: {
    width: 220, height: 220,
    backgroundColor: 'rgba(109,40,217,0.06)',
    bottom: 80, left: -60,
  },

  logoIconWrap: {
    width: 52, height: 52, borderRadius: 16,
    backgroundColor: 'rgba(79,140,255,0.12)',
    alignItems: 'center', justifyContent: 'center',
    marginBottom: 10,
    borderWidth: 1, borderColor: 'rgba(79,140,255,0.25)',
  },
  logoIcon: {fontSize: 26},
  logo: {
    color: '#FFFFFF', fontSize: 34, fontWeight: '800',
    letterSpacing: -1.2,
  },
  logoTagline: {color: '#3D5A80', fontSize: 13, marginTop: 3, letterSpacing: 0.3},

  card: {
    backgroundColor: '#0C1826',
    borderRadius: 28,
    padding: 26,
    borderWidth: 1,
    borderColor: 'rgba(79,140,255,0.12)',
    shadowColor: '#4F8CFF',
    shadowOpacity: 0.08,
    shadowRadius: 30,
    shadowOffset: {width: 0, height: 8},
    elevation: 10,
  },
  title: {color: 'white', fontSize: 26, fontWeight: '700', marginBottom: 4},
  subtitle2: {color: '#4A6080', fontSize: 14, marginBottom: 24},

  errorBanner: {
    backgroundColor: '#1F0C0D',
    borderRadius: 12,
    padding: 12,
    marginBottom: 16,
    borderLeftWidth: 3,
    borderLeftColor: '#E24B4A',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  errorIcon: {fontSize: 14},
  errorText: {color: '#F87171', fontSize: 13, flex: 1},

  labelRow: {flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4},
  inputWrap: {
    backgroundColor: '#0F1D30',
    borderRadius: 14, padding: 14,
    marginBottom: 14, borderWidth: 1, borderColor: '#1A2D45',
  },
  inputFocused: {borderColor: '#4F8CFF', backgroundColor: '#0D1B2E'},
  inputError: {borderColor: '#E24B4A', backgroundColor: '#120D0E'},
  inputLabel: {color: '#4F8CFF', fontSize: 11, fontWeight: '600', letterSpacing: 0.8},
  checkMark: {color: '#1D9E75', fontSize: 13, fontWeight: '700'},
  crossMark: {color: '#F87171', fontSize: 13, fontWeight: '700'},
  input: {color: 'white', fontSize: 15, padding: 0, marginTop: 2},
  passRow: {flexDirection: 'row', alignItems: 'center'},
  eyeBtn: {padding: 4},
  eyeText: {fontSize: 16},

  forgotWrap: {alignItems: 'flex-end', marginBottom: 22},
  forgot: {color: '#4F8CFF', fontSize: 13, fontWeight: '500'},

  button: {
    backgroundColor: '#4F8CFF',
    borderRadius: 14, padding: 16, alignItems: 'center',
    shadowColor: '#4F8CFF', shadowOpacity: 0.35,
    shadowRadius: 14, shadowOffset: {width: 0, height: 4},
    elevation: 6,
  },
  buttonLoading: {opacity: 0.75},
  buttonText: {color: 'white', fontWeight: '700', fontSize: 16},
  loadingRow: {flexDirection: 'row', alignItems: 'center'},

  biometricRow: {flexDirection: 'row', alignItems: 'center', marginVertical: 18, gap: 12},
  biometricWrap: {alignItems: 'center'},
  biometricBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    paddingVertical: 12, paddingHorizontal: 20,
    borderRadius: 14, borderWidth: 1, borderColor: '#1A2D45',
    backgroundColor: '#0F1D30',
  },
  biometricIcon: {fontSize: 20},
  biometricText: {color: '#7BA4D4', fontSize: 14, fontWeight: '600'},

  divider: {flexDirection: 'row', alignItems: 'center', marginVertical: 16, gap: 12},
  dividerLine: {flex: 1, height: 0.5, backgroundColor: '#1A2D45'},
  dividerText: {color: '#2E4A65', fontSize: 12, letterSpacing: 0.5},

  registerBtn: {
    borderWidth: 1, borderColor: '#1A3050',
    borderRadius: 14, padding: 15, alignItems: 'center',
    backgroundColor: 'rgba(79,140,255,0.04)',
  },
  registerText: {color: '#4F8CFF', fontWeight: '600', fontSize: 15},

  legalText: {textAlign: 'center', color: '#1E3047', fontSize: 11, marginTop: 24},
});
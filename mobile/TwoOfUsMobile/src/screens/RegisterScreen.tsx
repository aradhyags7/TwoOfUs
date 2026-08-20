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

function getStrength(pass: string): {level: number; label: string; color: string; hint: string} {
  if (pass.length === 0) return {level: 0, label: '', color: '#1E3A5F', hint: ''};
  if (pass.length < 6) return {level: 1, label: 'Too short', color: '#E24B4A', hint: 'Use at least 6 characters'};
  if (pass.length < 10 || !/[0-9]/.test(pass)) return {level: 2, label: 'Fair', color: '#EF9F27', hint: 'Add numbers for a stronger password'};
  if (!/[^a-zA-Z0-9]/.test(pass)) return {level: 3, label: 'Good', color: '#4F8CFF', hint: 'Add symbols to make it stronger'};
  if (pass.length >= 14) return {level: 5, label: 'Excellent', color: '#A78BFA', hint: 'Outstanding password!'};
  return {level: 4, label: 'Strong', color: '#1D9E75', hint: 'Great password!'};
}

function isValidEmail(val: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(val);
}

export default function RegisterScreen({navigation}: any) {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPass, setShowPass] = useState(false);
  const [loading, setLoading] = useState(false);
  const [focusedField, setFocusedField] = useState<string | null>(null);
  const [termsAccepted, setTermsAccepted] = useState(false);
  const [touched, setTouched] = useState<Record<string, boolean>>({});
  const [error, setError] = useState('');

  const fadeCard = useRef(new Animated.Value(0)).current;
  const slideCard = useRef(new Animated.Value(50)).current;
  const fadeLogo = useRef(new Animated.Value(0)).current;
  const logoScale = useRef(new Animated.Value(0.85)).current;
  const buttonScale = useRef(new Animated.Value(1)).current;
  const checkboxScale = useRef(new Animated.Value(1)).current;
  const errorOpacity = useRef(new Animated.Value(0)).current;
  const shakeAnim = useRef(new Animated.Value(0)).current;
  const orb1 = useRef(new Animated.Value(0)).current;
  const orb2 = useRef(new Animated.Value(0)).current;

  const strength = getStrength(password);
  const strengthWidth = useRef(new Animated.Value(0)).current;

  React.useEffect(() => {
    Animated.parallel([
      Animated.spring(logoScale, {toValue: 1, tension: 60, friction: 8, useNativeDriver: true}),
      Animated.timing(fadeLogo, {toValue: 1, duration: 800, useNativeDriver: true}),
      Animated.timing(fadeCard, {toValue: 1, duration: 700, delay: 200, useNativeDriver: true}),
      Animated.spring(slideCard, {toValue: 0, tension: 50, friction: 9, delay: 200, useNativeDriver: true}),
    ]).start();

    Animated.loop(
      Animated.sequence([
        Animated.timing(orb1, {toValue: 1, duration: 4500, useNativeDriver: true}),
        Animated.timing(orb1, {toValue: 0, duration: 4500, useNativeDriver: true}),
      ])
    ).start();
    Animated.loop(
      Animated.sequence([
        Animated.timing(orb2, {toValue: 1, duration: 6000, useNativeDriver: true}),
        Animated.timing(orb2, {toValue: 0, duration: 6000, useNativeDriver: true}),
      ])
    ).start();
  }, []);

  React.useEffect(() => {
    Animated.timing(strengthWidth, {
      toValue: strength.level / 5,
      duration: 350,
      useNativeDriver: false,
    }).start();
  }, [strength.level]);

  const shake = () => {
    Animated.sequence([
      Animated.timing(shakeAnim, {toValue: 12, duration: 55, useNativeDriver: true}),
      Animated.timing(shakeAnim, {toValue: -12, duration: 55, useNativeDriver: true}),
      Animated.timing(shakeAnim, {toValue: 8, duration: 55, useNativeDriver: true}),
      Animated.timing(shakeAnim, {toValue: 0, duration: 55, useNativeDriver: true}),
    ]).start();
  };

  const pressIn = () => Animated.spring(buttonScale, {toValue: 0.96, useNativeDriver: true, tension: 200}).start();
  const pressOut = () => Animated.spring(buttonScale, {toValue: 1, useNativeDriver: true, tension: 200}).start();

  const bounceCheckbox = () => {
    Animated.sequence([
      Animated.spring(checkboxScale, {toValue: 1.2, useNativeDriver: true, tension: 300}),
      Animated.spring(checkboxScale, {toValue: 1, useNativeDriver: true, tension: 200}),
    ]).start();
  };

  const isFocused = (f: string) => focusedField === f;
  const nameValid = touched.name ? name.trim().length >= 2 : null;
  const emailValid = touched.email ? isValidEmail(email) : null;
  const passValid = touched.password ? strength.level >= 3 : null;

  const handleRegister = async () => {
    setTouched({name: true, email: true, password: true});
    if (name.trim().length < 2 || !isValidEmail(email) || strength.level < 2 || !termsAccepted) {
      setError(!termsAccepted ? 'Please accept the Terms & Privacy Policy' : 'Please fill in all fields correctly');
      errorOpacity.setValue(0);
      Animated.timing(errorOpacity, {toValue: 1, duration: 250, useNativeDriver: true}).start();
      shake();
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

  const getFieldStatus = (field: string, valid: boolean | null) => {
    if (valid === null) return null;
    return valid ? 'valid' : 'invalid';
  };

  const fieldBorderColor = (status: string | null, focused: boolean) => {
    if (status === 'invalid') return '#E24B4A';
    if (focused || status === 'valid') return '#4F8CFF';
    return '#1A2D45';
  };

  const orb1Y = orb1.interpolate({inputRange: [0, 1], outputRange: [0, -22]});
  const orb2Y = orb2.interpolate({inputRange: [0, 1], outputRange: [0, 16]});

  const fields: Array<{key: 'name' | 'email' | 'password'; label: string; placeholder: string}> = [
    {key: 'name', label: 'Full Name', placeholder: 'Your name'},
    {key: 'email', label: 'Email', placeholder: 'you@example.com'},
    {key: 'password', label: 'Password', placeholder: '••••••••'},
  ];

  const fieldValues = {name, email, password};
  const fieldSetters = {
    name: (v: string) => { setName(v); if (touched.name) setTouched(t => ({...t, name: true})); },
    email: (v: string) => { setEmail(v); if (touched.email) setTouched(t => ({...t, email: true})); },
    password: (v: string) => { setPassword(v); if (touched.password) setTouched(t => ({...t, password: true})); },
  };
  const fieldValid = {name: nameValid, email: emailValid, password: passValid};

  return (
    <KeyboardAvoidingView style={{flex: 1}} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
      <ScrollView style={styles.container} contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">

        <Animated.View style={[styles.orb, styles.orb1, {transform: [{translateY: orb1Y}]}]} pointerEvents="none" />
        <Animated.View style={[styles.orb, styles.orb2, {transform: [{translateY: orb2Y}]}]} pointerEvents="none" />

        <Animated.View style={{opacity: fadeLogo, transform: [{scale: logoScale}], alignItems: 'center', marginBottom: 28}}>
          <View style={styles.logoIconWrap}>
            <Text style={styles.logoIcon}>💞</Text>
          </View>
          <Text style={styles.logo}>TwoOfUs</Text>
          <Text style={styles.logoTagline}>Your story, together</Text>
        </Animated.View>

        <Animated.View style={[styles.card, {opacity: fadeCard, transform: [{translateY: slideCard}, {translateX: shakeAnim}]}]}>
          <Text style={styles.title}>Create account</Text>
          <Text style={styles.subtitle2}>Join your partner on TwoOfUs</Text>

          {!!error && (
            <Animated.View style={[styles.errorBanner, {opacity: errorOpacity}]}>
              <Text style={styles.errorIcon}>⚠️</Text>
              <Text style={styles.errorText}>{error}</Text>
            </Animated.View>
          )}

          {fields.map(({key, label, placeholder}) => {
            const status = getFieldStatus(key, fieldValid[key]);
            const focused = isFocused(key);
            const borderColor = fieldBorderColor(status, focused);

            return (
              <View
                key={key}
                style={[styles.inputWrap, {borderColor}]}>

                <View style={styles.labelRow}>
                  <Text style={[styles.inputLabel, status === 'invalid' && {color: '#F87171'}]}>{label}</Text>
                  {status === 'valid' && (
                    <View style={styles.validBadge}><Text style={styles.checkMark}>✓</Text></View>
                  )}
                  {status === 'invalid' && (
                    <View style={styles.invalidBadge}><Text style={styles.crossMark}>✗</Text></View>
                  )}
                </View>

                <View style={styles.passRow}>
                  <TextInput
                    style={[styles.input, {flex: 1}]}
                    placeholder={placeholder}
                    placeholderTextColor="#2D4060"
                    value={fieldValues[key]}
                    onChangeText={fieldSetters[key]}
                    secureTextEntry={key === 'password' && !showPass}
                    autoCapitalize={key === 'name' ? 'words' : 'none'}
                    keyboardType={key === 'email' ? 'email-address' : 'default'}
                    onFocus={() => setFocusedField(key)}
                    onBlur={() => {
                      setFocusedField(null);
                      setTouched(t => ({...t, [key]: true}));
                    }}
                  />
                  {key === 'password' && (
                    <TouchableOpacity onPress={() => setShowPass(v => !v)} style={styles.eyeBtn}>
                      <Text style={styles.eyeText}>{showPass ? '🙈' : '👁️'}</Text>
                    </TouchableOpacity>
                  )}
                </View>

                {key === 'password' && password.length > 0 && (
                  <View style={styles.strengthContainer}>
                    <View style={styles.strengthSegments}>
                      {[1, 2, 3, 4, 5].map(seg => (
                        <View
                          key={seg}
                          style={[
                            styles.strengthSegment,
                            {backgroundColor: strength.level >= seg ? strength.color : '#1A2D45'},
                          ]}
                        />
                      ))}
                    </View>
                    <View style={styles.strengthMeta}>
                      <Text style={[styles.strengthLabel, {color: strength.color}]}>{strength.label}</Text>
                      {strength.hint ? <Text style={styles.strengthHint}>{strength.hint}</Text> : null}
                    </View>
                  </View>
                )}

                {key === 'name' && status === 'invalid' && (
                  <Text style={styles.fieldError}>Name must be at least 2 characters</Text>
                )}
                {key === 'email' && status === 'invalid' && (
                  <Text style={styles.fieldError}>Please enter a valid email address</Text>
                )}
              </View>
            );
          })}

          {/* Terms */}
          <TouchableOpacity
            style={styles.termsRow}
            onPress={() => {
              setTermsAccepted(v => !v);
              bounceCheckbox();
            }}
            activeOpacity={0.8}>
            <Animated.View
              style={[
                styles.checkbox,
                termsAccepted && styles.checkboxChecked,
                {transform: [{scale: checkboxScale}]},
              ]}>
              {termsAccepted && <Text style={styles.checkboxTick}>✓</Text>}
            </Animated.View>
            <Text style={styles.termsText}>
              I agree to the{' '}
              <Text style={styles.termsLink}>Terms of Service</Text>
              {' '}and{' '}
              <Text style={styles.termsLink}>Privacy Policy</Text>
            </Text>
          </TouchableOpacity>

          <Animated.View style={{transform: [{scale: buttonScale}]}}>
            <TouchableOpacity
              style={[styles.button, loading && styles.buttonLoading]}
              onPress={handleRegister}
              onPressIn={pressIn}
              onPressOut={pressOut}
              activeOpacity={1}
              disabled={loading}>
              {loading ? (
                <View style={styles.loadingRow}>
                  <ActivityIndicator color="white" size="small" />
                  <Text style={[styles.buttonText, {marginLeft: 10}]}>Creating account…</Text>
                </View>
              ) : (
                <Text style={styles.buttonText}>Create Account</Text>
              )}
            </TouchableOpacity>
          </Animated.View>

          <TouchableOpacity style={styles.loginWrap} onPress={() => navigation.goBack()}>
            <Text style={styles.loginText}>Already have an account? </Text>
            <Text style={styles.loginLink}>Sign in →</Text>
          </TouchableOpacity>
        </Animated.View>

        <Text style={styles.legalText}>Your data is encrypted and never shared</Text>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {flex: 1, backgroundColor: '#060E1A'},
  scroll: {flexGrow: 1, justifyContent: 'center', padding: 24, paddingBottom: 48},

  orb: {position: 'absolute', borderRadius: 999},
  orb1: {width: 260, height: 260, backgroundColor: 'rgba(79,140,255,0.07)', top: -40, right: -70},
  orb2: {width: 200, height: 200, backgroundColor: 'rgba(167,139,250,0.06)', bottom: 100, left: -50},

  logoIconWrap: {
    width: 52, height: 52, borderRadius: 16,
    backgroundColor: 'rgba(79,140,255,0.12)',
    alignItems: 'center', justifyContent: 'center',
    marginBottom: 10, borderWidth: 1, borderColor: 'rgba(79,140,255,0.25)',
  },
  logoIcon: {fontSize: 26},
  logo: {color: '#FFFFFF', fontSize: 34, fontWeight: '800', letterSpacing: -1.2},
  logoTagline: {color: '#3D5A80', fontSize: 13, marginTop: 3, letterSpacing: 0.3},

  card: {
    backgroundColor: '#0C1826', borderRadius: 28, padding: 26,
    borderWidth: 1, borderColor: 'rgba(79,140,255,0.12)',
    shadowColor: '#4F8CFF', shadowOpacity: 0.08,
    shadowRadius: 30, shadowOffset: {width: 0, height: 8}, elevation: 10,
  },
  title: {color: 'white', fontSize: 26, fontWeight: '700', marginBottom: 4},
  subtitle2: {color: '#4A6080', fontSize: 14, marginBottom: 24},

  errorBanner: {
    backgroundColor: '#1F0C0D', borderRadius: 12, padding: 12, marginBottom: 16,
    borderLeftWidth: 3, borderLeftColor: '#E24B4A',
    flexDirection: 'row', alignItems: 'center', gap: 8,
  },
  errorIcon: {fontSize: 14},
  errorText: {color: '#F87171', fontSize: 13, flex: 1},

  labelRow: {flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4},
  inputWrap: {
    backgroundColor: '#0F1D30', borderRadius: 14, padding: 14,
    marginBottom: 14, borderWidth: 1,
  },
  inputLabel: {color: '#4F8CFF', fontSize: 11, fontWeight: '600', letterSpacing: 0.8},

  validBadge: {
    width: 20, height: 20, borderRadius: 10,
    backgroundColor: 'rgba(29,158,117,0.2)', alignItems: 'center', justifyContent: 'center',
  },
  invalidBadge: {
    width: 20, height: 20, borderRadius: 10,
    backgroundColor: 'rgba(226,75,74,0.2)', alignItems: 'center', justifyContent: 'center',
  },
  checkMark: {color: '#1D9E75', fontSize: 11, fontWeight: '800'},
  crossMark: {color: '#F87171', fontSize: 11, fontWeight: '800'},
  fieldError: {color: '#F87171', fontSize: 11, marginTop: 6},

  input: {color: 'white', fontSize: 15, padding: 0, marginTop: 2},
  passRow: {flexDirection: 'row', alignItems: 'center'},
  eyeBtn: {padding: 4},
  eyeText: {fontSize: 16},

  strengthContainer: {marginTop: 12},
  strengthSegments: {flexDirection: 'row', gap: 4, marginBottom: 6},
  strengthSegment: {flex: 1, height: 4, borderRadius: 2},
  strengthMeta: {flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center'},
  strengthLabel: {fontSize: 12, fontWeight: '700'},
  strengthHint: {fontSize: 11, color: '#3D5A80', flex: 1, textAlign: 'right'},

  termsRow: {flexDirection: 'row', alignItems: 'flex-start', gap: 12, marginBottom: 20, marginTop: 4},
  checkbox: {
    width: 20, height: 20, borderRadius: 6,
    borderWidth: 1.5, borderColor: '#2A4060',
    backgroundColor: '#0F1D30', alignItems: 'center', justifyContent: 'center',
    marginTop: 1,
  },
  checkboxChecked: {backgroundColor: '#4F8CFF', borderColor: '#4F8CFF'},
  checkboxTick: {color: 'white', fontSize: 11, fontWeight: '800'},
  termsText: {color: '#4A6080', fontSize: 13, flex: 1, lineHeight: 19},
  termsLink: {color: '#4F8CFF', fontWeight: '600'},

  button: {
    backgroundColor: '#4F8CFF', borderRadius: 14, padding: 16, alignItems: 'center',
    shadowColor: '#4F8CFF', shadowOpacity: 0.35,
    shadowRadius: 14, shadowOffset: {width: 0, height: 4}, elevation: 6,
  },
  buttonLoading: {opacity: 0.75},
  buttonText: {color: 'white', fontWeight: '700', fontSize: 16},
  loadingRow: {flexDirection: 'row', alignItems: 'center'},

  loginWrap: {flexDirection: 'row', justifyContent: 'center', marginTop: 20},
  loginText: {color: '#4A6080', fontSize: 14},
  loginLink: {color: '#4F8CFF', fontSize: 14, fontWeight: '600'},

  legalText: {textAlign: 'center', color: '#1E3047', fontSize: 11, marginTop: 24},
});
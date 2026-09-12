// Port of btools.expressions.BExpression (BRouter v1.7.10).

import '../jfloat.dart';
import '../jvm.dart';
import 'b_expression_context.dart';

/// Every `float` operation rounds through [f32] exactly where the JVM
/// rounds: the result of `+ - * /` on two floats (double arithmetic on two
/// float values followed by one rounding to float is the IEEE float result,
/// since binary64 has more than twice the precision of binary32).
class BExpression {
  static const int _orExp = 10;
  static const int _andExp = 11;
  static const int _notExp = 12;

  static const int _addExp = 20;
  static const int _multiplyExp = 21;
  static const int _divideExp = 22;
  static const int _maxExp = 23;
  static const int _equalExp = 24;
  static const int _greaterExp = 25;
  static const int _minExp = 26;

  static const int _subExp = 27;
  static const int _lesserExp = 28;
  static const int _xorExp = 29;

  static const int _switchExp = 30;
  static const int _assignExp = 31;
  static const int _lookupExp = 32;
  static const int _numberExp = 33;
  static const int _variableExp = 34;
  static const int _foreignVariableExp = 35;
  static const int _variableGetExp = 36;

  int typ = 0;
  BExpression? op1;
  BExpression? op2;
  BExpression? op3;
  double numberValue = 0;
  int variableIdx = 0;
  int lookupNameIdx = -1;
  List<int>? lookupValueIdxArray;
  bool doNotChange = false;

  // Parse the expression and all subexpression
  static BExpression? parse(BExpressionContext ctx, int level) {
    return _parse(ctx, level, null);
  }

  static BExpression? _parse(
    BExpressionContext ctx,
    int level,
    String? optionalToken,
  ) {
    var e = _parseRaw(ctx, level, optionalToken);
    if (e == null) {
      return null;
    }

    if (_assignExp == e.typ) {
      // manage assined an injected values
      final assignedBefore = ctx.lastAssignedExpression![e.variableIdx];
      if (assignedBefore != null && assignedBefore.doNotChange) {
        e.op1 = assignedBefore; // was injected as key-value
        e.op1!.doNotChange =
            false; // protect just once, can be changed in second assignement
      }
      ctx.lastAssignedExpression![e.variableIdx] = e.op1;
    } else if (!ctx.skipConstantExpressionOptimizations) {
      // try to simplify the expression
      if (_variableExp == e.typ) {
        final ae = ctx.lastAssignedExpression![e.variableIdx];
        if (ae != null && ae.typ == _numberExp) {
          e = ae;
        }
      } else {
        final eCollapsed = e._tryCollapse();
        if (!identical(e, eCollapsed)) {
          e = eCollapsed; // allow breakpoint..
        }
        final eEvaluated = e._tryEvaluateConstant();
        if (!identical(e, eEvaluated)) {
          e = eEvaluated; // allow breakpoint..
        }
      }
    }
    if (level == 0) {
      // mark the used lookups after the
      // expression is collapsed to not mark
      // lookups as used that appear in the profile
      // but are de-activated by constant expressions
      final nodeCount = e._markLookupIdxUsed(ctx);
      ctx.expressionNodeCount += nodeCount;
    }
    return e;
  }

  int _markLookupIdxUsed(BExpressionContext ctx) {
    var nodeCount = 1;
    if (lookupNameIdx >= 0) {
      ctx.markLookupIdxUsed(lookupNameIdx);
    }
    if (op1 != null) {
      nodeCount += op1!._markLookupIdxUsed(ctx);
    }
    if (op2 != null) {
      nodeCount += op2!._markLookupIdxUsed(ctx);
    }
    if (op3 != null) {
      nodeCount += op3!._markLookupIdxUsed(ctx);
    }
    return nodeCount;
  }

  static BExpression? _parseRaw(
    BExpressionContext ctx,
    int level,
    String? optionalToken,
  ) {
    var brackets = false;
    var operator = ctx.parseToken();
    if (optionalToken != null && optionalToken == operator) {
      operator = ctx.parseToken();
    }
    if ('(' == operator) {
      brackets = true;
      operator = ctx.parseToken();
    }

    if (operator == null) {
      if (level == 0) return null;
      throw ArgumentError('unexpected end of file');
    }

    if (level == 0) {
      if ('assign' != operator) {
        throw ArgumentError(
          "operator $operator is invalid on toplevel (only 'assign' allowed)",
        );
      }
    }

    final exp = BExpression();
    var nops = 3;

    var ifThenElse = false;

    if ('switch' == operator) {
      exp.typ = _switchExp;
    } else if ('if' == operator) {
      exp.typ = _switchExp;
      ifThenElse = true;
    } else {
      nops = 2; // check binary expressions

      if ('or' == operator) {
        exp.typ = _orExp;
      } else if ('and' == operator) {
        exp.typ = _andExp;
      } else if ('multiply' == operator) {
        exp.typ = _multiplyExp;
      } else if ('divide' == operator) {
        exp.typ = _divideExp;
      } else if ('add' == operator) {
        exp.typ = _addExp;
      } else if ('max' == operator) {
        exp.typ = _maxExp;
      } else if ('min' == operator) {
        exp.typ = _minExp;
      } else if ('equal' == operator) {
        exp.typ = _equalExp;
      } else if ('greater' == operator) {
        exp.typ = _greaterExp;
      } else if ('sub' == operator) {
        exp.typ = _subExp;
      } else if ('lesser' == operator) {
        exp.typ = _lesserExp;
      } else if ('xor' == operator) {
        exp.typ = _xorExp;
      } else {
        nops = 1; // check unary expressions
        if ('assign' == operator) {
          if (level > 0) {
            throw ArgumentError('assign operator within expression');
          }
          exp.typ = _assignExp;
          final variable = ctx.parseToken();
          if (variable == null) throw ArgumentError('unexpected end of file');
          if (variable.contains('=')) {
            throw ArgumentError("variable name cannot contain '=': $variable");
          }
          if (variable.contains(':')) {
            throw ArgumentError(
              'cannot assign context-prefixed variable: $variable',
            );
          }
          exp.variableIdx = ctx.getVariableIdx(variable, true);
          if (exp.variableIdx < ctx.getMinWriteIdx()) {
            throw ArgumentError('cannot assign to readonly variable $variable');
          }
        } else if ('not' == operator) {
          exp.typ = _notExp;
        } else {
          nops = 0; // check elemantary expressions
          var idx = operator.indexOf('=');
          if (idx >= 0) {
            exp.typ = _lookupExp;
            final name = operator.substring(0, idx);
            final values = operator.substring(idx + 1);

            exp.lookupNameIdx = ctx.getLookupNameIdx(name);
            if (exp.lookupNameIdx < 0) {
              throw ArgumentError('unknown lookup name: $name');
            }
            // StringTokenizer(values, "|")
            final tokens = values
                .split('|')
                .where((t) => t.isNotEmpty)
                .toList();
            final nt = tokens.length;
            final nt2 = nt == 0 ? 1 : nt;
            final arr = List<int>.filled(nt2, 0);
            exp.lookupValueIdxArray = arr;
            for (var ti = 0; ti < nt2; ti++) {
              final value = ti < nt ? tokens[ti] : '';
              arr[ti] = ctx.getLookupValueIdx(exp.lookupNameIdx, value);
              if (arr[ti] < 0) {
                throw ArgumentError('unknown lookup value: $value');
              }
            }
          } else if ((idx = operator.indexOf(':')) >= 0) {
            /*
            use of variable values
            assign no_height
               switch and not      maxheight=
                        lesser v:maxheight  my_height  true
            false
             */
            if (operator.startsWith('v:')) {
              final name = operator.substring(2);
              exp.typ = _variableGetExp;
              exp.lookupNameIdx = ctx.getLookupNameIdx(name);
            } else {
              final context = operator.substring(0, idx);
              final varname = operator.substring(idx + 1);
              exp.typ = _foreignVariableExp;
              exp.variableIdx = ctx.getForeignVariableIdx(context, varname);
            }
          } else if ((idx = ctx.getVariableIdx(operator, false)) >= 0) {
            exp.typ = _variableExp;
            exp.variableIdx = idx;
          } else if ('true' == operator) {
            exp.numberValue = 1.0;
            exp.typ = _numberExp;
          } else if ('false' == operator) {
            exp.numberValue = 0.0;
            exp.typ = _numberExp;
          } else {
            try {
              exp.numberValue = javaParseFloat(operator);
              exp.typ = _numberExp;
            } on NumberFormatException {
              throw ArgumentError('unknown expression: $operator');
            }
          }
        }
      }
    }
    // parse operands
    if (nops > 0) {
      exp.op1 = _parse(ctx, level + 1, exp.typ == _assignExp ? '=' : null);
    }
    if (nops > 1) {
      if (ifThenElse) _checkExpectedToken(ctx, 'then');
      exp.op2 = _parse(ctx, level + 1, null);
    }
    if (nops > 2) {
      if (ifThenElse) _checkExpectedToken(ctx, 'else');
      exp.op3 = _parse(ctx, level + 1, null);
    }
    if (brackets) {
      _checkExpectedToken(ctx, ')');
    }
    return exp;
  }

  static void _checkExpectedToken(BExpressionContext ctx, String expected) {
    final token = ctx.parseToken();
    if (expected != token) {
      throw ArgumentError('unexpected token: $token, expected: $expected');
    }
  }

  // Evaluate the expression
  double evaluate(BExpressionContext? ctx) {
    switch (typ) {
      case _orExp:
        return op1!.evaluate(ctx) != 0.0
            ? 1.0
            : (op2!.evaluate(ctx) != 0.0 ? 1.0 : 0.0);
      case _xorExp:
        return ((op1!.evaluate(ctx) != 0.0) ^ (op2!.evaluate(ctx) != 0.0))
            ? 1.0
            : 0.0;
      case _andExp:
        return op1!.evaluate(ctx) != 0.0
            ? (op2!.evaluate(ctx) != 0.0 ? 1.0 : 0.0)
            : 0.0;
      case _addExp:
        return f32(op1!.evaluate(ctx) + op2!.evaluate(ctx));
      case _subExp:
        return f32(op1!.evaluate(ctx) - op2!.evaluate(ctx));
      case _multiplyExp:
        return f32(op1!.evaluate(ctx) * op2!.evaluate(ctx));
      case _divideExp:
        return _divide(op1!.evaluate(ctx), op2!.evaluate(ctx));
      case _maxExp:
        return _max(op1!.evaluate(ctx), op2!.evaluate(ctx));
      case _minExp:
        return _min(op1!.evaluate(ctx), op2!.evaluate(ctx));
      case _equalExp:
        return op1!.evaluate(ctx) == op2!.evaluate(ctx) ? 1.0 : 0.0;
      case _greaterExp:
        return op1!.evaluate(ctx) > op2!.evaluate(ctx) ? 1.0 : 0.0;
      case _lesserExp:
        return op1!.evaluate(ctx) < op2!.evaluate(ctx) ? 1.0 : 0.0;
      case _switchExp:
        return op1!.evaluate(ctx) != 0.0
            ? op2!.evaluate(ctx)
            : op3!.evaluate(ctx);
      case _assignExp:
        return ctx!.assign(variableIdx, op1!.evaluate(ctx));
      case _lookupExp:
        return ctx!.getLookupMatch(lookupNameIdx, lookupValueIdxArray!);
      case _numberExp:
        return numberValue;
      case _variableExp:
        return ctx!.getVariableValueByIdx(variableIdx);
      case _foreignVariableExp:
        return ctx!.getForeignVariableValue(variableIdx);
      case _variableGetExp:
        return ctx!.getLookupValue(lookupNameIdx);
      case _notExp:
        return op1!.evaluate(ctx) == 0.0 ? 1.0 : 0.0;
      default:
        throw ArgumentError('unknown op-code: $typ');
    }
  }

  // Try to collapse the expression
  // if logically possible
  BExpression _tryCollapse() {
    switch (typ) {
      case _orExp:
        return _numberExp == op1!.typ
            ? (op1!.numberValue != 0.0 ? op1! : op2!)
            : (_numberExp == op2!.typ
                  ? (op2!.numberValue != 0.0 ? op2! : op1!)
                  : this);
      case _andExp:
        return _numberExp == op1!.typ
            ? (op1!.numberValue == 0.0 ? op1! : op2!)
            : (_numberExp == op2!.typ
                  ? (op2!.numberValue == 0.0 ? op2! : op1!)
                  : this);
      case _addExp:
        return _numberExp == op1!.typ
            ? (op1!.numberValue == 0.0 ? op2! : this)
            : (_numberExp == op2!.typ
                  ? (op2!.numberValue == 0.0 ? op1! : this)
                  : this);
      case _switchExp:
        return _numberExp == op1!.typ
            ? (op1!.numberValue == 0.0 ? op3! : op2!)
            : this;
      default:
        return this;
    }
  }

  // Try to evaluate the expression
  // if all operands are constant
  BExpression _tryEvaluateConstant() {
    if (op1 != null &&
        _numberExp == op1!.typ &&
        (op2 == null || _numberExp == op2!.typ) &&
        (op3 == null || _numberExp == op3!.typ)) {
      final exp = BExpression();
      exp.typ = _numberExp;
      exp.numberValue = evaluate(null);
      return exp;
    }
    return this;
  }

  double _max(double v1, double v2) {
    return v1 > v2 ? v1 : v2;
  }

  double _min(double v1, double v2) {
    return v1 < v2 ? v1 : v2;
  }

  double _divide(double v1, double v2) {
    if (v2 == 0.0) throw ArgumentError('div by zero');
    return f32(v1 / v2);
  }

  @override
  String toString() {
    if (typ == _numberExp) {
      return javaFloatToString(numberValue);
    }
    if (typ == _variableExp) {
      return 'vidx=$variableIdx';
    }
    final sb = StringBuffer('typ=$typ ops=(');
    _addOp(sb, op1);
    _addOp(sb, op2);
    _addOp(sb, op3);
    sb.write(')');
    return sb.toString();
  }

  void _addOp(StringBuffer sb, BExpression? e) {
    if (e != null) {
      sb.write('[');
      sb.write(e.toString());
      sb.write(']');
    }
  }

  static BExpression createAssignExpressionFromKeyValue(
    BExpressionContext ctx,
    String key,
    String value,
  ) {
    final e = BExpression();
    e.typ = _assignExp;
    e.variableIdx = ctx.getVariableIdx(key, true);
    final op1 = BExpression();
    e.op1 = op1;
    op1.typ = _numberExp;
    op1.numberValue = javaParseFloat(value);
    op1.doNotChange = true;
    ctx.lastAssignedExpression![e.variableIdx] = op1;
    return e;
  }
}

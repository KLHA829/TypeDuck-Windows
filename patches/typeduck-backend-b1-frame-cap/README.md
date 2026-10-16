# TypeDuck-Windows-backend B1 patch

Apply on a checkout of `TypeDuck-Windows-backend` when the Cloud Agent cannot push to that repository.

```powershell
git checkout -b cursor/backend-b1-b2-bea9
git am path\to\typeduck-backend-b1-frame-cap.patch
git push -u origin cursor/backend-b1-b2-bea9
```

Then open a pull request on the backend repository.
